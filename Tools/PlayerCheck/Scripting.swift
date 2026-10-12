import AppKit
import AutoHushKit
import ScriptablePlayers
import VLCSupport

// MARK: - Scripting dictionary

/// What AutoHush's ScriptablePlayers need: pause and play in the app's own
/// suite (`<suite>Paus`, `<suite>Play`), the `player state` property (pPlS)
/// with stopped/playing/paused (kPSS, kPSP, kPSp), and `sound volume` (pVol)
/// for fades.
struct Scripting {
    var commands: [String: String] = [:]   // code → name
    /// The application's own properties: an app's state is read there only
    /// (QuickTime Player's `playing` is each document's, not the app's).
    var properties: [String: String] = [:]
    var enumerators: Set<String> = []
    /// The commands that must be told which document to act on (QuickTime
    /// Player's play and pause: "play document 1"), by code.
    var documentCommands: Set<String> = []
    /// The document class's code, and its `playing` property's (QuickTime
    /// Player: "docu", "play").
    var documentClass: String?
    var documentPlaying: String?

    var suite: String? {
        let pauses = Set(commands.keys.filter { $0.hasSuffix("Paus") }.map { String($0.prefix(4)) })
        let plays = Set(commands.keys.filter { $0.hasSuffix("Play") }.map { String($0.prefix(4)) })
        return pauses.intersection(plays).sorted().first
    }
    var hasPlayerState: Bool { properties["pPlS"] != nil }
    /// A true/false `playing` property instead (VLC's): its state too.
    var hasPlayingFlag: Bool { properties.values.contains("playing") }
    var hasStateValues: Bool { enumerators.isSuperset(of: ["kPSS", "kPSP", "kPSp"]) }
    /// Played and paused through its documents, each with its own `playing`
    /// (QuickTime Player): it plays while one does.
    var playsDocuments: Bool {
        documentClass != nil && documentPlaying != nil
            && ["pause", "play"].allSatisfy { commandCode($0).map(documentCommands.contains) == true }
    }
    /// Whether its state can be read by script: `player state`, a `playing`
    /// flag, or its documents'.
    var hasState: Bool { hasPlayerState || hasPlayingFlag || playsDocuments }
    var hasVolume: Bool { properties["pVol"] != nil }
    /// A `current track` (pTrk) with a name: what it plays, by script.
    var hasCurrentTrack: Bool { properties["pTrk"] != nil }
    /// Else a property of its own naming it (VLC's `name of current item`,
    /// AANA): its panel row shows that name too, wherever its window is.
    var currentItemName: String? { properties.first { $0.value == "name of current item" }?.key }
    /// Whether it says by script what it plays (`scriptedSong`).
    var namesItsSong: Bool { hasCurrentTrack || currentItemName != nil }
    var fitsScriptablePlayer: Bool { suite != nil && hasPlayerState && hasStateValues }
    /// A command's code ("spfyPaus") by its name: the app's own suite's
    /// first, as ScriptablePlayers sends it.
    func commandCode(_ name: String) -> String? {
        let codes = commands.filter { $0.value.lowercased() == name.lowercased() }.keys.sorted()
        return codes.first { $0.hasPrefix(suite ?? "????") } ?? codes.first
    }
}

/// Why the dictionary wasn't read, when it wasn't.
@MainActor var scriptingNote: String?

/// The app's dictionary: the .sdef its Info.plist names, else one in its
/// resources, read as it is (running `sdef` takes about 0.15 s); else as
/// `sdef` prints it, from an aete or old .scriptSuite files, but only while
/// the app runs: `sdef` opens an app to ask it, and this tool never launches
/// one, as AutoHush never does. `nil` when it has none.
@MainActor func readScripting(_ url: URL) -> Scripting? {
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
           let found = parseDictionary(document) {
            return found
        }
    }
    guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { !$0.isTerminated }) else {
        if bundleHasDictionary(url) { scriptingNote = "its dictionary is read from the app itself, so only while it runs" }
        return nil
    }
    let sdef = Process()
    sdef.executableURL = URL(fileURLWithPath: "/usr/bin/sdef")
    sdef.arguments = [url.path]
    let output = Pipe()
    sdef.standardOutput = output
    sdef.standardError = FileHandle.nullDevice
    guard (try? sdef.run()) != nil else { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    sdef.waitUntilExit()
    guard sdef.terminationStatus == 0, let document = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]) else { return nil }
    return parseDictionary(document)
}

/// The commands, properties and enumerators of a dictionary's XML; `nil`
/// with neither commands nor properties.
func parseDictionary(_ document: XMLDocument) -> Scripting? {
    var scripting = Scripting()
    func attributes(_ xpath: String) -> [(code: String, name: String)] {
        ((try? document.nodes(forXPath: xpath)) ?? []).compactMap { node in
            guard let element = node as? XMLElement, let code = element.attribute(forName: "code")?.stringValue else { return nil }
            return (code, element.attribute(forName: "name")?.stringValue ?? "")
        }
    }
    for (code, name) in attributes("//command") { scripting.commands[code] = name }
    for (code, name) in attributes("//class[@name='application']/property | //class-extension[@extends='application']/property") {
        scripting.properties[code] = name
    }
    scripting.enumerators = Set(attributes("//enumerator").map(\.code))
    // A command whose direct parameter, not optional, is a document.
    for node in (try? document.nodes(forXPath: "//command[direct-parameter]")) ?? [] {
        guard let command = node as? XMLElement, let code = command.attribute(forName: "code")?.stringValue,
              let parameter = command.elements(forName: "direct-parameter").first,
              parameter.attribute(forName: "optional")?.stringValue != "yes" else { continue }
        let types = [parameter.attribute(forName: "type")?.stringValue]
            + parameter.elements(forName: "type").map { $0.attribute(forName: "type")?.stringValue }
        if types.contains("document") { scripting.documentCommands.insert(code) }
    }
    // An .sdef read as it is may only extend `document` (QuickTime Player's):
    // the class comes from Cocoa's standard suite, which it includes, as "docu".
    scripting.documentClass = attributes("//class[@name='document']").first?.code
        ?? (((try? document.nodes(forXPath: "//class-extension[@extends='document']")) ?? []).isEmpty ? nil : "docu")
    scripting.documentPlaying = attributes("//class[@name='document']/property[@name='playing']"
        + " | //class-extension[@extends='document']/property[@name='playing']").first?.code
    return scripting.commands.isEmpty && scripting.properties.isEmpty ? nil : scripting
}

/// Whether the bundle carries a dictionary: an .sdef (named by its
/// Info.plist, or in its resources) or the older .scriptSuite files (VLC's).
/// Without one, `sdef` has nothing to read but the running app's.
func bundleHasDictionary(_ url: URL) -> Bool {
    if Bundle(url: url)?.object(forInfoDictionaryKey: "OSAScriptingDefinition") != nil { return true }
    let resources = (try? FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent("Contents/Resources").path)) ?? []
    return resources.contains { $0.hasSuffix(".sdef") || $0.hasSuffix(".scriptSuite") }
}

/// The app's dictionary. A press by one way reads it when the bundle has
/// one: for the script way, and its scripted state is the quickest sure sign
/// of whether the app plays, for every way (what it reports to Now Playing
/// first opens macOS's log, about 0.6 s).
@MainActor let scripting = !pressingOneWay || bundleHasDictionary(appURL) ? readScripting(appURL) : nil

@MainActor func reportScripting() {
    say()
    say("Scripting Dictionary")
    if let scripting {
        let playLike = scripting.commands.filter { ["play", "pause", "playpause", "stop"].contains($0.value.lowercased()) }
        say("  commands: " + (playLike.isEmpty ? "no play or pause" : playLike.sorted { $0.key < $1.key }.map { "\($0.value) (\($0.key))" }.joined(separator: ", ")))
        say("  player state (pPlS): \(scripting.hasPlayerState ? "yes" : "no")"
            + (scripting.hasPlayerState ? ", values stopped/playing/paused: \(scripting.hasStateValues ? "yes" : "no")" : ""))
        say("  sound volume (pVol): \(scripting.hasVolume ? "yes, so it can fade" : "no, so no fades")")
        if scripting.playsDocuments {
            say("  its documents: pause and play act on one (“pause document 1”), and each says whether it's playing:"
                + " it plays while one does, a pause pauses those playing, a play plays the front one (or those a test paused)")
        }
        if let suite = scripting.suite { say("  pause and play share suite “\(suite)”") }
    } else if let scriptingNote {
        say("  not read: \(scriptingNote)")
    } else {
        say("  none: it can't be scripted")
    }
}

/// Its AppleScript commands to pause and play it: pause and play in its own
/// suite (what ScriptablePlayers needs), else commands named so, else one
/// that toggles (playpause, or VLC's play, which toggles).
@MainActor func scriptControls() -> (pause: String, play: String, toggles: Bool)? {
    guard let scripting else { return nil }
    if let suite = scripting.suite, let pause = scripting.commands[suite + "Paus"], let play = scripting.commands[suite + "Play"] {
        return (pause, play, false)
    }
    let names = Set(scripting.commands.values.map { $0.lowercased() })
    if names.contains("pause"), names.contains("play") { return ("pause", "play", false) }
    if names.contains("playpause") { return ("playpause", "playpause", true) }
    if names.contains("play") { return ("play", "play", true) }
    return nil
}

// MARK: - Apple events, as AutoHush sends them

/// Why AppleScript can't be used, when macOS refuses it (no Automation permission).
@MainActor var scriptProblem: String?

/// -1743: macOS refused the Apple event (the Automation permission).
@MainActor func noteScriptError(_ number: Int) {
    if number == -1743 {
        scriptProblem = "macOS doesn't let this tool (or the app running it) control \(appName) by AppleScript: allow it in System Settings → Privacy & Security → Automation"
    }
}

/// AutoHush's Apple event codes (`ScriptablePlayer.Code`): the standard
/// suites', and the keywords of events, replies and object specifiers.
typealias EventCode = ScriptablePlayer.Code

/// A code read from a dictionary at run time as a number ("spfy" →
/// 0x73706679): ScriptablePlayers' `fourCharCode` takes only literals.
func osType(_ text: String) -> FourCharCode {
    text.utf8.prefix(4).reduce(0) { $0 << 8 | FourCharCode($1) }
}

/// A code as its four characters, as an app's dictionary writes it.
func fourCharacters(_ code: FourCharCode) -> String {
    String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, encoding: .macOSRoman) ?? "?"
}

/// The object specifier for the property `code` of `container`: of the
/// application as AutoHush builds it (`ScriptablePlayer.propertySpecifier`,
/// "player state"), else of what `container` names ("name of current
/// track", "playing of every document").
func propertySpecifier(_ code: String, of container: NSAppleEventDescriptor? = nil) -> NSAppleEventDescriptor {
    let specifier = ScriptablePlayer.propertySpecifier(osType(code))
    if let container { specifier.setDescriptor(container, forKeyword: EventCode.container) }
    return specifier
}

/// Whether macOS lets this tool (or the app running it) send the app Apple
/// events, asked before the first, as AutoHush asks when a player is chosen
/// (`AutomationPermission`): a send waits only 5 s, too short for someone
/// reading macOS's prompt. Allowed or denied, it's said once and kept
/// (`automationAnswer`; a test's Permissions ask it first); any other answer
/// (the app still starting: -600) is asked again before the next event. Nil
/// when allowed; else the error the event gets instead.
@MainActor func automationRefusal(pid: pid_t) -> NSError? {
    switch automationAnswer {
    case .allowed?: return nil
    case .denied?: return NSError(domain: NSOSStatusErrorDomain, code: Int(errAEEventNotPermitted))
    default: break
    }
    let status = AutomationPermission.check(pid: pid, ask: true)
    let answer = AutomationPermission(status: status)
    // A press's output is its one line of result: there it's only logged.
    let note: (String) -> Void = action == nil ? { say($0) } : { log($0) }
    switch answer {
    case .allowed:
        automationAnswer = answer
        note("  Automation for \(appName): allowed")
        return nil
    case .denied:
        automationAnswer = answer
        noteScriptError(-1743)
        note("  Automation for \(appName): not allowed: allow it in System Settings → Privacy & Security → Automation")
        return NSError(domain: NSOSStatusErrorDomain, code: Int(errAEEventNotPermitted))
    case .notAsked, .notRunning:
        return NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
}

/// An Apple event error as AutoHush words it (`ScriptablePlayer.mapError`,
/// with the app's own message when it gave one), with macOS's number:
/// "error -1743 (Automation permission … not granted)".
func eventError(_ error: NSError) -> String {
    let mapped = ScriptablePlayer.mapError(number: error.code, message: error.userInfo[NSLocalizedFailureReasonErrorKey] as? String)
    if case .playerCommandFailed(.appleEventError(_, let message?)) = mapped { return "error \(error.code) (\(message))" }
    if case .playerCommandFailed = mapped { return "error \(error.code)" }
    return "error \(error.code) (\(mapped.localizedDescription))"
}

/// Sends the app the Apple event `makeEvent` builds for its process, as
/// AutoHush's `AppleEventChannel` sends one: to the running process, so an
/// event can never launch the app, waiting `AppleEventChannel.replyTimeout`
/// (5 s) for the reply, once Automation is allowed (`automationRefusal`).
/// The reply's direct object, or the error number, with the app's message
/// as `ScriptablePlayer.replyError` reads it (-1743: macOS refused it;
/// -600: it isn't running).
@MainActor func sendAppleEvent(_ makeEvent: (pid_t) -> NSAppleEventDescriptor) -> Result<NSAppleEventDescriptor?, NSError> {
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { !$0.isTerminated })?
        .processIdentifier else { return .failure(NSError(domain: NSOSStatusErrorDomain, code: Int(procNotFound))) }
    if let refusal = automationRefusal(pid: pid) { return .failure(refusal) }
    do {
        let reply = try makeEvent(pid).sendEvent(options: [.waitForReply, .canInteract], timeout: AppleEventChannel.replyTimeout)
        if let number = reply.paramDescriptor(forKeyword: EventCode.errorNumber)?.int32Value, number != 0 {
            let message = reply.paramDescriptor(forKeyword: EventCode.errorString)?.stringValue
            return .failure(NSError(domain: NSOSStatusErrorDomain, code: Int(number),
                                    userInfo: message.map { [NSLocalizedFailureReasonErrorKey: $0] } ?? [:]))
        }
        return .success(reply.paramDescriptor(forKeyword: EventCode.directObject))
    } catch {
        return .failure(error as NSError)
    }
}

/// `get <property>` of the application, as AutoHush asks a player's state
/// or volume (`ScriptablePlayer.makeGetPropertyEvent`).
@MainActor func getProperty(_ code: String) -> Result<NSAppleEventDescriptor?, NSError> {
    sendAppleEvent { ScriptablePlayer.makeGetPropertyEvent(osType(code), processIdentifier: $0) }
}

/// `set <property> to <value>` of the application, as AutoHush sets a
/// player's volume (`ScriptablePlayer.makeSetPropertyEvent`); nil once set.
@MainActor func setProperty(_ code: String, to value: Int) -> NSError? {
    if case .failure(let error) = sendAppleEvent({ ScriptablePlayer.makeSetPropertyEvent(osType(code), to: value, processIdentifier: $0) }) {
        return error
    }
    return nil
}

/// `get` of what `specifier` names (a document's property, the current
/// track's name): AutoHush's get event with that direct object.
@MainActor func getData(of specifier: NSAppleEventDescriptor) -> Result<NSAppleEventDescriptor?, NSError> {
    sendAppleEvent { pid in
        let event = ScriptablePlayer.makeCommandEvent(suite: EventCode.coreSuite, EventCode.getData, processIdentifier: pid)
        event.setParam(specifier, forKeyword: EventCode.directObject)
        return event
    }
}

/// One of its dictionary's commands by code ("spfyPaus": suite, then
/// command), as AutoHush sends pause and play (`ScriptablePlayer.makeCommandEvent`),
/// told which document to act on when it needs one; nil once sent.
@MainActor func sendCommand(_ code: String, to target: NSAppleEventDescriptor? = nil) -> NSError? {
    let result = sendAppleEvent { pid in
        let event = ScriptablePlayer.makeCommandEvent(suite: osType(String(code.prefix(4))), osType(String(code.suffix(4))),
                                                      processIdentifier: pid)
        if let target { event.setParam(target, forKeyword: EventCode.directObject) }
        return event
    }
    if case .failure(let error) = result { return error }
    return nil
}

/// The object specifier for the app's documents: every one, or one by name
/// or by index (1: the front one), as AppleScript builds "document 1".
@MainActor func documentSpecifier(named name: String? = nil, index: Int? = nil) -> NSAppleEventDescriptor {
    let record = NSAppleEventDescriptor.record()
    let specifier = record.coerce(toDescriptorType: EventCode.objectSpecifier) ?? record
    specifier.setDescriptor(NSAppleEventDescriptor(typeCode: osType(scripting?.documentClass ?? "docu")), forKeyword: EventCode.desiredClass)
    specifier.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: EventCode.container)
    if let name {
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: osType("name")), forKeyword: EventCode.keyForm)
        specifier.setDescriptor(NSAppleEventDescriptor(string: name), forKeyword: EventCode.keyData)
    } else {
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: osType("indx")), forKeyword: EventCode.keyForm)
        if let index {
            specifier.setDescriptor(NSAppleEventDescriptor(int32: Int32(index)), forKeyword: EventCode.keyData)
        } else {
            var all = osType("all ")
            specifier.setDescriptor(NSAppleEventDescriptor(descriptorType: osType("abso"), bytes: &all, length: 4)!,
                                    forKeyword: EventCode.keyData)
        }
    }
    return specifier
}

/// A reply's items: a list's, else the one value.
func items(_ descriptor: NSAppleEventDescriptor?) -> [NSAppleEventDescriptor] {
    guard let descriptor else { return [] }
    guard descriptor.descriptorType == typeAEList else { return [descriptor] }
    return descriptor.numberOfItems > 0 ? (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0) } : []
}

/// Its open documents by script (QuickTime Player's), front first: each
/// one's name and whether it's playing.
@MainActor func scriptedDocuments() -> Result<[(name: String, playing: Bool)], NSError> {
    guard let playing = scripting?.documentPlaying else { return .success([]) }
    let every = documentSpecifier()
    switch (getData(of: propertySpecifier("pnam", of: every)), getData(of: propertySpecifier(playing, of: every))) {
    case (.failure(let error), _), (_, .failure(let error)):
        return .failure(error)
    case (.success(let names), .success(let flags)):
        return .success(zip(items(names), items(flags)).map { ($0.stringValue ?? "", $1.booleanValue) })
    }
}

/// The documents a test's pause paused, by name: its play plays them again.
@MainActor var pausedDocuments: [String] = []

/// macOS refused the app's state (-1743): it's no longer asked. Each kind of
/// error, and each unknown state value, is said once.
@MainActor var scriptRefused = false
@MainActor var scriptErrorsSaid: Set<Int> = []
@MainActor var unknownStatesSaid: Set<FourCharCode> = []

/// The app's state by script, when its dictionary has it and it answers:
/// its `player state` (stopped, playing, paused, as Spotify's, read as
/// AutoHush reads it: `ScriptablePlayer.playerState(fromEnumCode:)`, which
/// counts Music's fast forwarding and rewinding as playing), else its
/// `playing` flag (VLC's: playing or paused), else its documents'
/// (QuickTime Player's: playing while one is, stopped with none open),
/// asked by Apple event. Only macOS refusing it (-1743: no Automation
/// permission for whatever runs this tool) stops the asking; another error
/// (a timeout, -1712, from a busy VLC) counts for that look only.
@MainActor func scriptedState() -> PlayerState? {
    guard let scripting, scripting.hasState, !scriptRefused else { return nil }
    func failed(_ error: NSError) -> PlayerState? {
        noteScriptError(error.code)
        let refused = error.code == -1743
        if refused { scriptRefused = true }
        if scriptErrorsSaid.insert(error.code).inserted {
            say("  its state can't be read by script: \(eventError(error))" + (refused ? "" : " (asked again at the next look)"))
        }
        return nil
    }
    if !scripting.hasPlayerState, !scripting.hasPlayingFlag {
        switch scriptedDocuments() {
        case .failure(let error): return failed(error)
        case .success(let documents): return documents.isEmpty ? .stopped : documents.contains(where: \.playing) ? .playing : .paused
        }
    }
    let property = scripting.hasPlayerState ? "pPlS" : scripting.properties.first { $0.value == "playing" }!.key
    switch getProperty(property) {
    case .failure(let error):
        return failed(error)
    case .success(let result):
        guard let result else { return nil }
        guard scripting.hasPlayerState else {
            if result.booleanValue { return .playing }
            // Not playing: VLC's `current time` is -1 with no item, so it's
            // stopped, else paused, as AutoHush's VLCPlayer tells them apart.
            guard let time = scripting.properties.first(where: { $0.value == "current time" })?.key,
                  case .success(let reply?) = getProperty(time)
            else { return .paused }
            let state = VLCPlayer.state(playing: false, currentTime: Int(reply.int32Value))
            return state == .unknown ? .paused : state
        }
        let code = result.enumCodeValue
        let state = ScriptablePlayer.playerState(fromEnumCode: code)
        if state == .unknown, unknownStatesSaid.insert(code).inserted {
            say("  its state reads “\(fourCharacters(code))”, a value AutoHush doesn't know: taken as not playing")
        }
        return state
    }
}

/// The name of what it plays, by Apple event, when its dictionary has a
/// `current track` (Spotify's, Music's, TV's), else a `name of current item`
/// (VLC's). It stays while paused, where a window's title may not (a paused
/// Spotify's says "Spotify Premium"), and it's read wherever its window is
/// (VLC's on another desktop can't be reached by Accessibility).
/// Nil without one, or when it doesn't answer (nothing loaded).
@MainActor func scriptedSong() -> String? {
    guard let scripting, scripting.namesItsSong, !scriptRefused else { return nil }
    let specifier = scripting.hasCurrentTrack || scripting.currentItemName == nil
        ? propertySpecifier("pnam", of: propertySpecifier("pTrk")) : propertySpecifier(scripting.currentItemName!)
    switch getData(of: specifier) {
    case .failure(let error):
        noteScriptError(error.code)
        return nil
    case .success(let result):
        return result?.stringValue
    }
}

/// Sends the app one of its dictionary's commands (by name: "pause", "play",
/// "playpause"), as an Apple event; false (and why) when it fails. One that
/// acts on a document (QuickTime Player's) goes to each playing one for a
/// pause or stop, and for a play to those a test paused, else the front one.
@MainActor func sendScript(_ command: String) -> Bool {
    guard let code = scripting?.commandCode(command) else {
        say("    \(command): not in its dictionary")
        return false
    }
    func failed(_ error: NSError) -> Bool {
        noteScriptError(error.code)
        say("    \(command): \(eventError(error))")
        return false
    }
    guard scripting?.documentCommands.contains(code) == true else {
        if let error = sendCommand(code) { return failed(error) }
        return true
    }
    let documents: [(name: String, playing: Bool)]
    switch scriptedDocuments() {
    case .failure(let error): return failed(error)
    case .success(let found): documents = found
    }
    let stopping = ["pause", "stop"].contains(command.lowercased())
    var targets: [NSAppleEventDescriptor]
    if stopping {
        let playing = documents.filter(\.playing).map(\.name)
        if command.lowercased() == "pause" { pausedDocuments = playing }
        targets = playing.map { documentSpecifier(named: $0) }
    } else {
        let paused = pausedDocuments.filter { name in documents.contains { $0.name == name } }
        targets = paused.map { documentSpecifier(named: $0) }
        if targets.isEmpty, !documents.isEmpty { targets = [documentSpecifier(index: 1)] }
        pausedDocuments = []
    }
    guard !targets.isEmpty else {
        say("    \(command): no document \(stopping ? "playing" : "open")")
        return false
    }
    for target in targets {
        if let error = sendCommand(code, to: target) { return failed(error) }
    }
    return true
}

/// Whether its volume can be read and set as fades need it, checked once
/// while a test has it paused (silent): its `sound volume` (Spotify's,
/// Music's), else its `audio volume` (VLC's, 0–512), set one step away and
/// read back, then put back. An app that reads back another number than it
/// was set to (Spotify: one less) needs the profile's `readVolume`, or each
/// fade restoring the volume it read loses a step. It's put back however
/// the change went: a change refused or not read back may still have taken.
@MainActor var volumeChecked = false
@MainActor func checkVolume() {
    guard !volumeChecked, let scripting,
          let (code, name) = scripting.properties.first(where: { $0.value == "sound volume" })
              .map({ ($0.key, $0.value) }) ?? scripting.properties.first(where: { $0.value == "audio volume" }).map({ ($0.key, $0.value) })
    else { return }
    volumeChecked = true
    func read() -> Int? {
        guard case .success(let reply?) = getProperty(code) else { return nil }
        return Int(reply.int32Value)
    }
    guard let start = read() else { say("    volume (“\(name)”): can't be read: no fades"); return }
    let target = start > 1 ? start - 1 : start + 1
    let setError = setProperty(code, to: target)
    // Music drops a change that follows another within a moment (measured:
    // set 99 then 100 at once, it stays at 99; 0.2 s apart, it takes both).
    Thread.sleep(forTimeInterval: 0.3)
    let back = read()
    // Put back as it was: an app that reads one less is set one more.
    let offset = setError == nil ? (back.map { $0 - target } ?? 0) : 0
    var restored = back
    for _ in 0..<2 where restored != start {
        _ = setProperty(code, to: start - offset)
        Thread.sleep(forTimeInterval: 0.3)
        restored = read()
    }
    let putBack = restored == start ? "; put back to \(start)"
        : "; couldn't put it back: it reads \(restored.map(String.init) ?? "?") (was \(start))"
    if let setError {
        say("    volume (“\(name)”): \(start), can't be set (\(eventError(setError))): no fades" + (back == start ? "" : putBack))
        return
    }
    guard let back else { say("    volume (“\(name)”): set to \(target), then can't be read: no fades" + putBack); return }
    say("    volume (“\(name)”): \(start); set to \(target), it reads \(back): "
        + (offset == 0 ? "reads back as set, so it can fade"
           : "reads \(abs(offset)) \(offset < 0 ? "less" : "more") than set (as Spotify, one less): the profile needs readVolume")
        + putBack
        + (name == "audio volume" ? " (its own scale: VLC's goes to 512)" : ""))
}

// MARK: - State notifications

/// The usual names of a player's state notification: Spotify's
/// `<bundle ID>.PlaybackStateChanged`, Music's `<bundle ID>.playerInfo`, and
/// their likely variants. macOS delivers a distributed notification only to
/// observers that name it (one with no name gets nothing, measured on macOS
/// 27), so a name outside this list can't be seen.
let stateNotificationSuffixes = ["PlaybackStateChanged", "playbackStateChanged", "playerInfo", "PlayerInfo",
                                 "PlayerStateChanged", "playerStateChanged", "PlayStateChanged", "playStateChanged"]

/// The state notifications seen, with their userInfo keys, and what each
/// announced: the state in its "Player State", as AutoHush's ScriptablePlayers
/// read it (`PlayerStateObserver`), which is how AutoHush follows such a
/// player instead of asking it. Delivered while the run loop runs; behind a
/// lock rather than the main actor, so where macOS delivers them doesn't matter.
final class NotificationLog: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var seenKeys: [String: Set<String>] = [:]
    /// Each one with a state, in order: its name, the state, when.
    private var announcements: [(name: String, state: PlayerState, at: Date)] = []
    init(bundleID: String) {
        super.init()
        for suffix in stateNotificationSuffixes {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(note(_:)), name: Notification.Name("\(bundleID).\(suffix)"), object: nil,
                suspensionBehavior: .deliverImmediately)
        }
    }
    @objc func note(_ notification: Notification) {
        let keys = (notification.userInfo ?? [:]).keys.map { "\($0)" }
        let state = PlayerStateObserver.playerState(from: notification.userInfo)
        lock.withLock {
            seenKeys[notification.name.rawValue, default: []].formUnion(keys)
            if state != .unknown { announcements.append((notification.name.rawValue, state, Date())) }
        }
    }
    /// The notifications seen, with their userInfo keys.
    var seen: [String: Set<String>] { lock.withLock { seenKeys } }
    /// What was announced since `date`, in order.
    func announced(since date: Date) -> [(name: String, state: PlayerState, at: Date)] {
        lock.withLock { announcements.filter { $0.at >= date } }
    }
    /// The last state announced since `date`; Music posts each change twice,
    /// the state before, then the new one.
    func lastState(since date: Date) -> PlayerState? { announced(since: date).last?.state }
}

/// The notifications followed through a test.
@MainActor var notifications: NotificationLog?

/// The notification that announced both a trial's pause and its play: what
/// a ScriptablePlayerProfile names (`stateNotification`).
@MainActor var announcingNotification: String?

/// What the notifications announced since `date`, for a trial's line.
@MainActor func announcementLine(since date: Date) -> String? {
    guard let notifications else { return nil }
    let said = notifications.announced(since: date)
    // Silence is worth saying only of an app AutoHush would follow by its notification.
    guard !said.isEmpty else { return scripting?.fitsScriptablePlayer == true ? "    notifications: none announced it" : nil }
    return "    announced: " + said.map { $0.state.rawValue }.joined(separator: ", then ") + " (\(said.last!.name))"
}
