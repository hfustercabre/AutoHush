import AppKit
import Foundation
import AutoHushKit

/// An app controlled by AppleScript as its dictionary allows it
/// (`ScriptSetup`), found by a check rather than described by a profile:
/// its own pause and play, else a command that toggles (sent only from the
/// opposite state), to its documents when they act on one (QuickTime
/// Player's). Its state is its `player state`, its `playing` flag or its
/// documents'; its notification follows it when the check saw one,
/// otherwise it's read about once a second. One whose state can't be read
/// by script toggles by `toggleState`, the app's other signs.
package actor ScriptedAppPlayer: MusicPlayer {
    package nonisolated let bundleID: String
    package nonisolated let name: String
    package nonisolated let setup: ScriptSetup
    /// The notification that announced its pauses and plays in the check;
    /// `nil` when none did.
    package nonisolated let stateNotification: Notification.Name?

    private let channel: any AppleEventSending
    /// For a toggle without a scripted state: whether it plays, as the
    /// app's other signs tell it (`.unknown`: nothing is sent).
    private let toggleState: @Sendable () async -> PlayerState
    /// The documents its last pause paused, by name: its play plays them again.
    private var pausedDocuments: [String] = []
    /// The last read's failure, logged once until a read works or fails otherwise.
    private var lastFailure: String?
    private let logger = AutoHushLogger(category: "ScriptedAppPlayer")

    /// `channel`: its Apple events; tests stand in for it.
    package init(bundleID: String, name: String, setup: ScriptSetup, stateNotification: Notification.Name? = nil,
                 toggleState: @escaping @Sendable () async -> PlayerState = { .unknown }, channel: (any AppleEventSending)? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.setup = setup
        self.stateNotification = stateNotification
        self.toggleState = toggleState
        self.channel = channel ?? AppleEventChannel(bundleID: bundleID, label: name)
    }

    package nonisolated var canFade: Bool { setup.hasVolume }

    package func verifyControlAccess() async throws {
        let pid = try channel.runningProcessIdentifier()
        try await channel.requestPermission(pid: pid)
    }

    package func playerState() async -> PlayerState {
        guard let pid = channel.processIdentifier() else { return .notRunning }
        do {
            let state = try await readState(of: pid)
            lastFailure = nil
            return state
        } catch {
            // Polled once a second: a read that keeps failing (Automation
            // denied, the app busy) is logged once, not every second.
            let failure = String(describing: error)
            if failure != lastFailure { logger.error("\(self.name, privacy: .public) playerState failed: \(error)") }
            lastFailure = failure
            return .unknown
        }
    }

    private func readState(of pid: pid_t) async throws -> PlayerState {
        switch setup.state {
        case nil:
            return .unknown
        case .playerState:
            return ScriptablePlayer.playerState(fromReply: try await channel.send(ScriptablePlayer.makeGetPlayerStateEvent(processIdentifier:), to: pid))
        case .playingFlag(let property, let currentTime):
            let playing = try await get(property, of: pid)
            if playing.directObjectBoolean == true { return .playing }
            // Not playing: -1 for its current time means nothing is loaded.
            guard let currentTime, let time = try await get(currentTime, of: pid).directObjectInteger else { return .paused }
            return time < 0 ? .stopped : .paused
        case .documents:
            let documents = try await documents(of: pid)
            return documents.isEmpty ? .stopped : documents.contains(where: \.playing) ? .playing : .paused
        }
    }

    package func pause() async throws {
        switch setup.commands {
        case .pauseAndPlay(let pause, _):
            try await send(pause, pausing: true)
        case .toggle(let toggle):
            guard try await stateForToggle().needsToggle(from: .playing) else { return }
            try await send(toggle, pausing: true)
        }
    }

    package func play() async throws {
        switch setup.commands {
        case .pauseAndPlay(_, let play):
            try await send(play, pausing: false)
        case .toggle(let toggle):
            guard try await stateForToggle().needsToggle(from: .paused) else { return }
            try await send(toggle, pausing: false)
        }
    }

    /// Its state before a toggle: by script, else by its other signs.
    private func stateForToggle() async -> PlayerState {
        setup.state == nil ? await toggleState() : await playerState()
    }

    package func volume() async -> Int? {
        guard setup.hasVolume, let pid = channel.processIdentifier(),
              let reply = try? await channel.send(ScriptablePlayer.makeGetVolumeEvent(processIdentifier:), to: pid)
        else { return nil }
        return ScriptablePlayer.volume(fromReply: reply, reading: { $0 })
    }

    package func setVolume(_ volume: Int) async throws {
        guard setup.hasVolume else { return }
        let volume = min(max(volume, 0), 100)
        let pid = try channel.runningProcessIdentifier()
        _ = try await channel.send({ ScriptablePlayer.makeSetVolumeEvent(volume, processIdentifier: $0) }, to: pid)
    }

    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        if let stateNotification {
            return PlayerStateObserver(notification: stateNotification, bundleID: bundleID, onChange: onChange)
        }
        return PolledStateObserver(read: { [self] in await self.playerState() }, onChange: onChange)
    }

    package nonisolated var stateReportDelay: TimeInterval { stateNotification == nil ? PolledStateObserver.reportDelay : 0 }

    // MARK: - Apple events

    /// Sends the command `code` ("spfyPaus"); to documents when its commands
    /// act on one: a pause to each one playing (noted), a play to those it
    /// paused that are still open, else the front one.
    private func send(_ code: String, pausing: Bool) async throws {
        let pid = try channel.runningProcessIdentifier()
        guard setup.actsOnDocuments, case .documents(let documentClass, _) = setup.state else {
            _ = try await channel.send({ ScriptedAppPlayer.makeCommandEvent(code, processIdentifier: $0) }, to: pid)
            return
        }
        let documents = try await documents(of: pid)
        let targets: [String?]
        if pausing {
            pausedDocuments = documents.filter(\.playing).map(\.name)
            targets = pausedDocuments
        } else {
            let paused = pausedDocuments.filter { name in documents.contains { $0.name == name } }
            targets = paused.isEmpty ? (documents.isEmpty ? [] : [nil]) : paused
            pausedDocuments = []
        }
        guard !targets.isEmpty else { throw MusicPlayerError.playerCommandFailed(.nothingToPlay) }
        for target in targets {
            _ = try await channel.send({
                ScriptedAppPlayer.makeCommandEvent(code, to: ScriptedAppPlayer.documentSpecifier(documentClass, named: target), processIdentifier: $0)
            }, to: pid)
        }
    }

    private func get(_ property: String, of pid: pid_t) async throws -> PlayerReply {
        try await channel.send({ ScriptablePlayer.makeGetPropertyEvent(ScriptedAppPlayer.code(property), processIdentifier: $0) }, to: pid)
    }

    /// Its open documents, front first: each one's name and whether it plays.
    private func documents(of pid: pid_t) async throws -> [(name: String, playing: Bool)] {
        guard case .documents(let documentClass, let playing) = setup.state else { return [] }
        let names = try await channel.send({
            ScriptedAppPlayer.makeGetDataEvent(ScriptedAppPlayer.propertySpecifier("pnam", of: ScriptedAppPlayer.documentSpecifier(documentClass)),
                                               processIdentifier: $0)
        }, to: pid)
        let flags = try await channel.send({
            ScriptedAppPlayer.makeGetDataEvent(ScriptedAppPlayer.propertySpecifier(playing, of: ScriptedAppPlayer.documentSpecifier(documentClass)),
                                               processIdentifier: $0)
        }, to: pid)
        // One document answers with its value, not a list of one.
        let nameList = names.listTexts.isEmpty ? names.directObjectText.map { [$0] } ?? [] : names.listTexts
        let flagList = flags.listBooleans.isEmpty ? flags.directObjectBoolean.map { [$0] } ?? [] : flags.listBooleans
        return Array(zip(nameList, flagList).map { (name: $0, playing: $1) })
    }
}
