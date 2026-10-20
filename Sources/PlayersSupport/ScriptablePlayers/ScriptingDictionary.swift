import AppKit
import Foundation
import AutoHushKit

/// An app's AppleScript dictionary, as Player Check reads it: its commands,
/// the application's properties, its enumerators, and how it acts on its
/// documents. What a player set up from a check is controlled with
/// (`ScriptSetup`), for an app without a profile of its own.
package struct ScriptingDictionary: Equatable, Sendable {
    /// Each command's name by its code ("spfyPaus": "pause").
    package var commands: [String: String] = [:]
    /// The application's own properties, by code: an app's state is read
    /// there only (QuickTime Player's `playing` is each document's).
    package var properties: [String: String] = [:]
    var enumerators: Set<String> = []
    /// The commands that must be told which document to act on (QuickTime
    /// Player's play and pause: "play document 1"), by code.
    var documentCommands: Set<String> = []
    /// The document class's code, and its `playing` property's (QuickTime
    /// Player: "docu", "play").
    var documentClass: String?
    var documentPlaying: String?

    init() {}

    /// The app's own suite, which holds both pause and play ("spfy").
    package var suite: String? {
        let pauses = Set(commands.keys.filter { $0.hasSuffix("Paus") }.map { String($0.prefix(4)) })
        let plays = Set(commands.keys.filter { $0.hasSuffix("Play") }.map { String($0.prefix(4)) })
        return pauses.intersection(plays).sorted().first
    }
    /// A `player state` (pPlS), as Spotify's and Music's.
    package var hasPlayerState: Bool { properties["pPlS"] != nil }
    /// A true/false `playing` property instead (VLC's): its state too.
    var hasPlayingFlag: Bool { properties.values.contains("playing") }
    /// `player state`'s values: stopped, playing, paused.
    package var hasStateValues: Bool { enumerators.isSuperset(of: ["kPSS", "kPSP", "kPSp"]) }
    /// Played and paused through its documents, each with its own `playing`
    /// (QuickTime Player): it plays while one does.
    package var playsDocuments: Bool {
        documentClass != nil && documentPlaying != nil
            && ["pause", "play"].allSatisfy { commandCode($0).map(documentCommands.contains) == true }
    }
    /// Whether its state can be read by script, as AutoHush reads it
    /// (`ScriptSetup.State`): `player state` with its three values, a
    /// `playing` flag, or its documents'.
    package var hasState: Bool { ScriptSetup.State(dictionary: self) != nil }
    /// A `sound volume` (pVol), 0–100, so it can fade.
    package var hasVolume: Bool { properties["pVol"] != nil }
    /// A `current track` (pTrk) with a name: what it plays, by script.
    package var hasCurrentTrack: Bool { properties["pTrk"] != nil }
    /// Else a property of its own naming it (VLC's `name of current item`).
    package var currentItemName: String? { properties.first { $0.value == "name of current item" }?.key }
    /// Whether it says by script what it plays.
    package var namesItsSong: Bool { hasCurrentTrack || currentItemName != nil }
    /// What a `ScriptablePlayerProfile` needs: pause and play in its own
    /// suite, and `player state` with its three values.
    package var fitsScriptablePlayer: Bool { suite != nil && hasPlayerState && hasStateValues }

    /// A command's code ("spfyPaus") by its name: the app's own suite's
    /// first, as ScriptablePlayers sends it.
    func commandCode(_ name: String) -> String? {
        let codes = commands.filter { $0.value.lowercased() == name.lowercased() }.keys.sorted()
        return codes.first { $0.hasPrefix(suite ?? "????") } ?? codes.first
    }

    // MARK: - Reading it

    /// How long `sdef` may take to ask a running app for its dictionary.
    static let sdefTimeout: TimeInterval = 10

    /// The dictionary of the app at `url`: the .sdef its Info.plist names,
    /// else one in its resources, read as it is; else, while the app runs
    /// (`sdef` would open it to ask it, and AutoHush never launches an app),
    /// as `sdef` prints it, from an aete or old .scriptSuite files. `nil`
    /// when it has none.
    package static func read(appAt url: URL, isRunning: Bool) -> ScriptingDictionary? {
        let bundle = Bundle(url: url)
        let named = (bundle?.object(forInfoDictionaryKey: "OSAScriptingDefinition") as? String).flatMap { name in
            bundle?.url(forResource: name, withExtension: nil)
                ?? bundle?.url(forResource: (name as NSString).deletingPathExtension, withExtension: "sdef")
        }
        let resources = url.appendingPathComponent("Contents/Resources")
        let inResources = ((try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? [])
            .filter { $0.hasSuffix(".sdef") }.sorted().map { resources.appendingPathComponent($0) }
        for file in [named].compactMap({ $0 }) + inResources {
            if let document = try? XMLDocument(contentsOf: file, options: [.nodeLoadExternalEntitiesNever]),
               let found = parse(document) {
                return found
            }
        }
        guard isRunning else { return nil }
        // Asked of the running app, which may be busy: at most `sdefTimeout`,
        // then it reads as having no dictionary.
        let sdef = ToolRun(URL(fileURLWithPath: "/usr/bin/sdef"), [url.path], timeout: Self.sdefTimeout).runBlocking()
        guard sdef.succeeded,
              let document = try? XMLDocument(data: sdef.output, options: [.nodeLoadExternalEntitiesNever]) else { return nil }
        return parse(document)
    }

    /// Whether the bundle carries a dictionary: an .sdef (named by its
    /// Info.plist, or in its resources) or the older .scriptSuite files
    /// (VLC's). Without one, `sdef` has nothing to read but the running app's.
    package static func isInBundle(at url: URL) -> Bool {
        if Bundle(url: url)?.object(forInfoDictionaryKey: "OSAScriptingDefinition") != nil { return true }
        let resources = (try? FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent("Contents/Resources").path)) ?? []
        return resources.contains { $0.hasSuffix(".sdef") || $0.hasSuffix(".scriptSuite") }
    }

    /// The commands, properties and enumerators of a dictionary's XML; `nil`
    /// with neither commands nor properties.
    static func parse(_ document: XMLDocument) -> ScriptingDictionary? {
        var dictionary = ScriptingDictionary()
        func attributes(_ xpath: String) -> [(code: String, name: String)] {
            ((try? document.nodes(forXPath: xpath)) ?? []).compactMap { node in
                guard let element = node as? XMLElement, let code = element.attribute(forName: "code")?.stringValue else { return nil }
                return (code, element.attribute(forName: "name")?.stringValue ?? "")
            }
        }
        for (code, name) in attributes("//command") { dictionary.commands[code] = name }
        for (code, name) in attributes("//class[@name='application']/property | //class-extension[@extends='application']/property") {
            dictionary.properties[code] = name
        }
        dictionary.enumerators = Set(attributes("//enumerator").map(\.code))
        // A command whose direct parameter, not optional, is a document.
        for node in (try? document.nodes(forXPath: "//command[direct-parameter]")) ?? [] {
            guard let command = node as? XMLElement, let code = command.attribute(forName: "code")?.stringValue,
                  let parameter = command.elements(forName: "direct-parameter").first,
                  parameter.attribute(forName: "optional")?.stringValue != "yes" else { continue }
            let types = [parameter.attribute(forName: "type")?.stringValue]
                + parameter.elements(forName: "type").map { $0.attribute(forName: "type")?.stringValue }
            if types.contains("document") { dictionary.documentCommands.insert(code) }
        }
        // An .sdef read as it is may only extend `document` (QuickTime Player's):
        // the class comes from Cocoa's standard suite, which it includes, as "docu".
        dictionary.documentClass = attributes("//class[@name='document']").first?.code
            ?? (((try? document.nodes(forXPath: "//class-extension[@extends='document']")) ?? []).isEmpty ? nil : "docu")
        dictionary.documentPlaying = attributes("//class[@name='document']/property[@name='playing']"
            + " | //class-extension[@extends='document']/property[@name='playing']").first?.code
        return dictionary.commands.isEmpty && dictionary.properties.isEmpty ? nil : dictionary
    }
}
