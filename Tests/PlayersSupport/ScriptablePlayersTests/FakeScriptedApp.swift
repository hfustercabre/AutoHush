import AppKit
import Foundation
import os
import AutoHushKit
@testable import ScriptablePlayers

/// An app scripted as its dictionary allows, without the app: its player
/// state or `playing` flag (`jPly`) with its current time (`jTim`), its
/// volume, its documents, the commands it was sent, and whether it answers.
final class FakeScriptedApp: AppleEventSending {
    struct State {
        var pid: pid_t? = 4242
        /// `kPSP` playing, `kPSp` paused; its `jPly` flag the same.
        var playing = true
        /// Its `jTim`: -1 with nothing loaded; `nil`, not a number.
        var currentTime: Int? = 12
        /// Its `pVol`, 0–100.
        var volume = 50
        /// Its open documents (`docu`, each with its `jPly`), front first.
        var documents: [(name: String, playing: Bool)] = []
        /// Each document's `audio volume` (`volu`, 0–1), by name; 1 unless set.
        var documentVolumes: [String: Double] = [:]
        var fails = false
        /// Its toggle is taken, but doesn't change it.
        var ignoresToggle = false
        /// What was sent: "ask" (for consent), "get pPlS", "set pVol 30",
        /// "get pnam of docu", or a command's code ("jukePaus"), with the
        /// document it went to ("jukePaus Song A", "jukePlay front").
        var sent: [String] = []
    }

    let state: OSAllocatedUnfairLock<State>

    init(_ change: (inout State) -> Void = { _ in }) {
        var initial = State()
        change(&initial)
        state = OSAllocatedUnfairLock(initialState: initial)
    }

    var sent: [String] { state.withLock { $0.sent } }
    /// What was sent but its reads and sets: the commands.
    var commands: [String] { sent.filter { entry in !["ask", "get ", "set "].contains { entry.hasPrefix($0) } } }

    func processIdentifier() -> pid_t? { state.withLock { $0.pid } }

    func runningProcessIdentifier() throws -> pid_t {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        return pid
    }

    func requestPermission(pid: pid_t) async throws { state.withLock { $0.sent.append("ask") } }

    func send(_ makeEvent: @escaping @Sendable (pid_t) -> NSAppleEventDescriptor, to pid: pid_t) async throws -> PlayerReply {
        // What the event asks, read before the lock: descriptors aren't Sendable.
        let event = makeEvent(pid)
        let code = Self.text(event.eventClass) + Self.text(event.eventID)
        let direct = event.paramDescriptor(forKeyword: fourCharCode("----"))
        let property = (direct?.forKeyword(fourCharCode("seld"))?.typeCodeValue).map(Self.text)
        let ofDocuments = direct?.forKeyword(fourCharCode("from")).map { $0.descriptorType != fourCharCode("null") } ?? false
        let value = event.paramDescriptor(forKeyword: fourCharCode("data")).map { Int($0.int32Value) }
        let real = event.paramDescriptor(forKeyword: fourCharCode("data"))?.doubleValue
        // A property's document: by its name, else the front one.
        let container = direct?.forKeyword(fourCharCode("from"))
        let propertyDocument = container.map { $0.forKeyword(fourCharCode("form"))?.enumCodeValue == fourCharCode("name")
            ? $0.forKeyword(fourCharCode("seld"))?.stringValue ?? "?" : "front" }
        // A command's document: by its name, else the front one (index 1).
        let document = direct.flatMap { $0.forKeyword(fourCharCode("form"))?.enumCodeValue == fourCharCode("name")
            ? $0.forKeyword(fourCharCode("seld"))?.stringValue : "front" }
        return try state.withLock { state in
            if state.fails { throw MusicPlayerError.playerNotResponding }
            switch (code, property) {
            case ("coregetd", "volu"?) where ofDocuments:
                let name = propertyDocument == "front" ? state.documents.first?.name : propertyDocument
                state.sent.append("get volu of \(propertyDocument ?? "?")")
                var reply = PlayerReply()
                reply.directObjectReal = name.map { state.documentVolumes[$0] ?? 1 }
                return reply
            case ("coresetd", "volu"?) where ofDocuments:
                let name = propertyDocument == "front" ? state.documents.first?.name : propertyDocument
                state.sent.append(String(format: "set volu of %@ %.2f", propertyDocument ?? "?", real ?? -1))
                if let name, let real { state.documentVolumes[name] = real }
                return PlayerReply()
            case ("coregetd", let property?) where ofDocuments:
                state.sent.append("get \(property) of docu")
                // One document answers with its value, not a list of one.
                let documents = state.documents
                if property == "pnam" {
                    var reply = PlayerReply(listTexts: documents.count == 1 ? [] : documents.map(\.name))
                    if documents.count == 1 { reply.directObjectText = documents[0].name }
                    return reply
                }
                return documents.count == 1 ? PlayerReply(directObjectBoolean: documents[0].playing)
                    : PlayerReply(listBooleans: documents.map(\.playing))
            case ("coregetd", let property?):
                state.sent.append("get \(property)")
                switch property {
                case "pPlS": return PlayerReply(directObjectCode: state.playing ? ScriptablePlayer.Code.statePlaying : ScriptablePlayer.Code.statePaused)
                case "pVol": return PlayerReply(directObjectInteger: state.volume)
                case "jPly": return PlayerReply(directObjectBoolean: state.playing)
                case "jTim": return PlayerReply(directObjectInteger: state.currentTime)
                default: return PlayerReply()
                }
            case ("coresetd", "pVol"?):
                state.sent.append("set pVol \(value ?? -1)")
                state.volume = value ?? state.volume
                return PlayerReply()
            default:
                state.sent.append(document.map { "\(code) \($0)" } ?? code)
                let playing: Bool? = switch code {
                case "jukeTogl": state.ignoresToggle ? nil : !state.playing
                case "jukePaus": false
                case "jukePlay": true
                default: nil
                }
                guard let playing else { return PlayerReply() }
                if let document {
                    let index = document == "front" ? state.documents.indices.first : state.documents.firstIndex { $0.name == document }
                    if let index { state.documents[index].playing = playing }
                } else {
                    state.playing = playing
                }
                return PlayerReply()
            }
        }
    }

    /// A four-char code as its text ("jukePaus" is "juke" and "Paus").
    private static func text(_ code: OSType) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, encoding: .macOSRoman) ?? "?"
    }
}
