import AppKit
import PlayerCheckKit
import os
import AutoHushKit
import ScriptablePlayers

// MARK: - Scripting dictionary

/// The app's AppleScript dictionary, read as AutoHush reads one for a
/// player set up from a check (`ScriptingDictionary`).
typealias Scripting = ScriptingDictionary

/// Why the dictionary wasn't read, when it wasn't.
@MainActor var scriptingNote: String?

/// The app's dictionary, as AutoHush reads it (`ScriptingDictionary.read`):
/// its .sdef as it is; else, as `sdef` prints it, only while the app runs:
/// `sdef` opens an app to ask it, and this tool never launches one, as
/// AutoHush never does. `nil` when it has none.
@MainActor func readScripting(_ url: URL) -> Scripting? {
    let running = NSRunningApplication.running(bundleID) != nil
    if let found = ScriptingDictionary.read(appAt: url, isRunning: running) { return found }
    if !running, ScriptingDictionary.isInBundle(at: url) {
        scriptingNote = "its dictionary is read from the app itself, so only while it runs"
    }
    return nil
}

/// The app's dictionary. A press by one way reads it when the bundle has
/// one: for the script way, and its scripted state is the quickest sure sign
/// of whether the app plays, for every way (what it reports to Now Playing
/// first opens macOS's log, about 0.6 s).
@MainActor let scripting = !pressingOneWay || ScriptingDictionary.isInBundle(at: appURL) ? readScripting(appURL) : nil

@MainActor func reportScripting() {
    say()
    say(CheckReportLine.Heading.scripting.rawValue)
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

/// How AutoHush would script it (`ScriptSetup(dictionary:)`, the setup a
/// check keeps): its commands, whether they act on its documents, and where
/// its state is read. Nil without play or pause commands.
@MainActor let scriptSetup = scripting.flatMap(ScriptSetup.init(dictionary:))

/// Where its state is read by script, as AutoHush reads it
/// (`ScriptSetup.State`), also without commands: it tells how the app plays
/// whichever way presses it. Nil when it can't be read by script.
@MainActor let scriptState = scripting.flatMap(ScriptSetup.State.init(dictionary:))

/// One of its AppleScript commands, as AutoHush sends it: by its code
/// ("spfyPaus"), named in the report as its dictionary names it ("pause").
/// `pauses`: sent to pause it (a toggle is sent both ways).
struct ScriptCommand: Equatable {
    let code: String
    let name: String
    let pauses: Bool
}

/// Its AppleScript commands to pause and play it, as AutoHush chooses them
/// (`ScriptSetup(dictionary:)`): pause and play in its own suite (what
/// ScriptablePlayers needs), else commands named so, else one that toggles
/// (playpause, or a play that toggles).
func scriptControls(of scripting: Scripting?) -> (pause: ScriptCommand, play: ScriptCommand, toggles: Bool)? {
    guard let scripting, let setup = ScriptSetup(dictionary: scripting) else { return nil }
    func command(_ code: String, pauses: Bool) -> ScriptCommand {
        ScriptCommand(code: code, name: scripting.commands[code] ?? code, pauses: pauses)
    }
    switch setup.commands {
    case .pauseAndPlay(let pause, let play): return (command(pause, pauses: true), command(play, pauses: false), false)
    case .toggle(let toggle): return (command(toggle, pauses: true), command(toggle, pauses: false), true)
    }
}

/// The app's AppleScript commands to pause and play it (`scriptControls(of:)`).
@MainActor func scriptControls() -> (pause: ScriptCommand, play: ScriptCommand, toggles: Bool)? { scriptControls(of: scripting) }

// MARK: - Apple events, as AutoHush sends them

// Built by ScriptablePlayers' own builders (`ScriptablePlayer`,
// `ScriptedAppPlayer+AppleEvents`), from the codes the dictionary gives as text.

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

/// A code as its four characters, as an app's dictionary writes it.
func fourCharacters(_ code: FourCharCode) -> String {
    String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, encoding: .macOSRoman) ?? "?"
}

/// The object specifier for the application's property `code` ("player
/// state", "current track"), as AutoHush builds it (`ScriptablePlayer.propertySpecifier`).
func propertySpecifier(_ code: String) -> NSAppleEventDescriptor {
    ScriptablePlayer.propertySpecifier(ScriptedAppPlayer.code(code))
}

/// Whether macOS lets this tool (or the app running it) send the app Apple
/// events, asked before the first, as AutoHush asks when a player is chosen
/// (`AutomationPermission`): a send waits only 5 s, too short for someone
/// reading macOS's prompt. Allowed or denied, it's said once and kept
/// (`automationAnswer`; a test's Permissions ask it first); any other answer
/// (-600: the app quit) is asked again before the next event. Nil when
/// allowed; else the error the event gets instead.
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

/// An Apple event error as AutoHush words it (`ScriptablePlayer.mapError`),
/// with macOS's number: "error -1743 (Automation permission … not granted)".
/// Never the app's own message, which can name what it was playing.
func eventError(_ error: NSError) -> String {
    let mapped = ScriptablePlayer.mapError(number: error.code)
    if case .playerCommandFailed = mapped { return "error \(error.code)" }
    return "error \(error.code) (\(mapped.localizedDescription))"
}

/// Sends the app the Apple event `makeEvent` builds for its process, as
/// AutoHush's `AppleEventChannel` sends one: to the running process, so an
/// event can never launch the app, waiting `AppleEventChannel.replyTimeout`
/// (5 s) for the reply, once Automation is allowed (`automationRefusal`).
/// The reply's direct object, or the error number, as
/// `ScriptablePlayer.replyError` reads it (-1743: macOS refused it; -600:
/// it isn't running).
@MainActor func sendAppleEvent(_ makeEvent: (pid_t) -> NSAppleEventDescriptor) -> Result<NSAppleEventDescriptor?, NSError> {
    guard let pid = NSRunningApplication.running(bundleID)?.processIdentifier else {
        return .failure(NSError(domain: NSOSStatusErrorDomain, code: Int(procNotFound)))
    }
    if let refusal = automationRefusal(pid: pid) { return .failure(refusal) }
    do {
        let reply = try makeEvent(pid).sendEvent(options: [.waitForReply, .canInteract], timeout: AppleEventChannel.replyTimeout)
        if let number = reply.paramDescriptor(forKeyword: EventCode.errorNumber)?.int32Value, number != 0 {
            return .failure(NSError(domain: NSOSStatusErrorDomain, code: Int(number)))
        }
        return .success(reply.paramDescriptor(forKeyword: EventCode.directObject))
    } catch {
        return .failure(error as NSError)
    }
}

/// `get <property>` of the application, as AutoHush asks a player's state
/// or volume (`ScriptablePlayer.makeGetPropertyEvent`).
@MainActor func getProperty(_ code: String) -> Result<NSAppleEventDescriptor?, NSError> {
    sendAppleEvent { ScriptablePlayer.makeGetPropertyEvent(ScriptedAppPlayer.code(code), processIdentifier: $0) }
}

/// `set <property> to <value>` of the application, as AutoHush sets a
/// player's volume (`ScriptablePlayer.makeSetPropertyEvent`); nil once set.
@MainActor func setProperty(_ code: String, to value: Int) -> NSError? {
    if case .failure(let error) = sendAppleEvent({ ScriptablePlayer.makeSetPropertyEvent(ScriptedAppPlayer.code(code), to: value, processIdentifier: $0) }) {
        return error
    }
    return nil
}

/// `get` of what `specifier` names (a document's property, the current
/// track's name), as AutoHush asks it (`ScriptedAppPlayer.makeGetDataEvent`).
@MainActor func getData(of specifier: NSAppleEventDescriptor) -> Result<NSAppleEventDescriptor?, NSError> {
    sendAppleEvent { ScriptedAppPlayer.makeGetDataEvent(specifier, processIdentifier: $0) }
}

/// One of its dictionary's commands by code ("abcdPaus": suite, then
/// command), as AutoHush sends pause and play (`ScriptedAppPlayer.makeCommandEvent`),
/// told which document to act on when it needs one; nil once sent.
@MainActor func sendCommand(_ code: String, to target: NSAppleEventDescriptor? = nil) -> NSError? {
    if case .failure(let error) = sendAppleEvent({ ScriptedAppPlayer.makeCommandEvent(code, to: target, processIdentifier: $0) }) {
        return error
    }
    return nil
}

/// A reply's items: a list's, else the one value.
func items(_ descriptor: NSAppleEventDescriptor?) -> [NSAppleEventDescriptor] {
    guard let descriptor else { return [] }
    guard descriptor.descriptorType == typeAEList else { return [descriptor] }
    return descriptor.numberOfItems > 0 ? (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0) } : []
}

/// Its open documents of class `documentClass` by script (an app that plays
/// documents), front first: each one's name and whether it's playing (its
/// property `playing`), as AutoHush reads them.
@MainActor func scriptedDocuments(_ documentClass: String, playing: String) -> Result<[(name: String, playing: Bool)], NSError> {
    let every = ScriptedAppPlayer.documentSpecifier(documentClass)
    switch (getData(of: ScriptedAppPlayer.propertySpecifier("pnam", of: every)),
            getData(of: ScriptedAppPlayer.propertySpecifier(playing, of: every))) {
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
/// Its state by script said it didn't play while it was heard (an app whose
/// `player state` reads stopped while it plays a stream, 2026-10-22): wrong
/// for this app, so it's no longer read, and AutoHush isn't given it
/// (`writeResult`): other signs tell its state.
@MainActor var scriptStateWrong = false
@MainActor var scriptErrorsSaid: Set<Int> = []
@MainActor var unknownStatesSaid: Set<FourCharCode> = []

/// The app's state by script, read where AutoHush reads it (`scriptState`)
/// and when it answers: its `player state`, only with its three standard
/// values (stopped, playing, paused, read as AutoHush reads it:
/// `ScriptablePlayer.playerState(fromEnumCode:)`, which counts fast
/// forwarding and rewinding as playing), else its `playing` flag (with its
/// `current time` telling stopped from paused), else its documents'
/// (playing while one is, stopped with none open), asked by Apple event.
/// Only macOS refusing it (-1743: no Automation permission for whatever
/// runs this tool), or its state found wrong (`scriptStateWrong`), stops the
/// asking; another error (a timeout, -1712, from a busy app) counts for that
/// look only.
@MainActor func scriptedState() -> PlayerState? {
    guard let scriptState, !scriptRefused, !scriptStateWrong else { return nil }
    func failed(_ error: NSError) -> PlayerState? {
        noteScriptError(error.code)
        let refused = error.code == -1743
        if refused { scriptRefused = true }
        if scriptErrorsSaid.insert(error.code).inserted {
            say("  its state can't be read by script: \(eventError(error))" + (refused ? "" : " (asked again at the next look)"))
        }
        return nil
    }
    switch scriptState {
    case .documents(let documentClass, let playing):
        switch scriptedDocuments(documentClass, playing: playing) {
        case .failure(let error): return failed(error)
        case .success(let documents): return ScriptSetup.State.state(documentsPlaying: documents.map(\.playing))
        }
    case .playingFlag(let playing, let currentTime):
        switch getProperty(playing) {
        case .failure(let error):
            return failed(error)
        case .success(let result):
            guard let result else { return nil }
            // Not playing: its `current time` tells stopped from paused, as
            // AutoHush reads it (an unread one: paused).
            var time: Int?
            if !result.booleanValue, let currentTime, case .success(let reply?) = getProperty(currentTime) { time = Int(reply.int32Value) }
            return ScriptSetup.State.state(playing: result.booleanValue, currentTime: time)
        }
    case .playerState:
        switch getProperty("pPlS") {
        case .failure(let error):
            return failed(error)
        case .success(let result):
            guard let result else { return nil }
            let code = result.enumCodeValue
            let state = ScriptablePlayer.playerState(fromEnumCode: code)
            if state == .unknown, unknownStatesSaid.insert(code).inserted {
                say("  its state reads “\(fourCharacters(code))”, a value AutoHush doesn't know: taken as not playing")
            }
            return state
        }
    }
}

/// The name of what it plays, by Apple event, when its dictionary has a
/// `current track`, else a `name of current item`. It stays while paused,
/// where a window's title may not (a paused app's may say just its name),
/// and it's read wherever its window is (one on another desktop may be out
/// of Accessibility's reach).
/// Nil without one, or when it doesn't answer (nothing loaded).
@MainActor func scriptedSong() -> String? {
    guard let scripting, scripting.namesItsSong, !scriptRefused else { return nil }
    let specifier = scripting.hasCurrentTrack || scripting.currentItemName == nil
        ? ScriptedAppPlayer.propertySpecifier("pnam", of: propertySpecifier("pTrk")) : propertySpecifier(scripting.currentItemName!)
    switch getData(of: specifier) {
    case .failure(let error):
        noteScriptError(error.code)
        return nil
    case .success(let result):
        return result?.stringValue
    }
}

/// Sends the app one of its AppleScript commands (`scriptControls`), as an
/// Apple event; false (and why) when it fails. To its documents as AutoHush
/// sends it (`ScriptedAppPlayer`), when its commands act on one and its
/// state is theirs: a pause to each playing one, a play to those a test
/// paused, else the front one.
@MainActor func sendScript(_ command: ScriptCommand) -> Bool {
    func failed(_ error: NSError) -> Bool {
        noteScriptError(error.code)
        say("    \(command.name): \(eventError(error))")
        return false
    }
    guard scriptSetup?.actsOnDocuments == true, case .documents(let documentClass, let playing)? = scriptSetup?.state else {
        if let error = sendCommand(command.code) { return failed(error) }
        return true
    }
    let documents: [(name: String, playing: Bool)]
    switch scriptedDocuments(documentClass, playing: playing) {
    case .failure(let error): return failed(error)
    case .success(let found): documents = found
    }
    var targets: [NSAppleEventDescriptor]
    if command.pauses {
        let playing = documents.filter(\.playing).map(\.name)
        pausedDocuments = playing
        targets = playing.map { ScriptedAppPlayer.documentSpecifier(documentClass, named: $0) }
    } else {
        let paused = pausedDocuments.filter { name in documents.contains { $0.name == name } }
        targets = paused.map { ScriptedAppPlayer.documentSpecifier(documentClass, named: $0) }
        if targets.isEmpty, !documents.isEmpty { targets = [ScriptedAppPlayer.documentSpecifier(documentClass, index: 1)] }
        pausedDocuments = []
    }
    guard !targets.isEmpty else {
        say("    \(command.name): no document \(command.pauses ? "playing" : "open")")
        return false
    }
    for target in targets {
        if let error = sendCommand(command.code, to: target) { return failed(error) }
    }
    return true
}

/// Whether its volume can be read and set as fades need it, checked once
/// while a test has it paused (silent): its `sound volume` (pVol, 0–100),
/// else its `audio volume` (a scale of its own), set one step away and read
/// back, then put back. An app that reads back another number than it was
/// set to (one less, say) needs its reading made up for (a profile's
/// `readVolume`), or each fade restoring the volume it read loses a step. It's put back however
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
    // An app may drop a change that follows another within a moment (measured:
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
           : "reads \(abs(offset)) \(offset < 0 ? "less" : "more") than set" + forDevelopers(": a ScriptablePlayerProfile needs readVolume"))
        + putBack
        + (name == "audio volume" ? " (a scale of its own" + (start > 100 ? ", above 100: it read \(start)" : "") + ")" : ""))
}

// MARK: - State notifications

/// The usual names of a player's state notification: the supported
/// scriptable players' (`<bundle ID>.PlaybackStateChanged`,
/// `<bundle ID>.playerInfo`) and their likely variants. macOS delivers a distributed notification only to
/// observers that name it (one with no name gets nothing, measured on macOS
/// 27), so a name outside this list can't be seen.
let stateNotificationSuffixes = ["PlaybackStateChanged", "playbackStateChanged", "playerInfo", "PlayerInfo",
                                 "PlayerStateChanged", "playerStateChanged", "PlayStateChanged", "playStateChanged"]

/// The state notifications seen, with their userInfo keys, and what each
/// announced: the state in its "Player State", as AutoHush's ScriptablePlayers
/// read it (`PlayerStateObserver`), which is how AutoHush follows such a
/// player instead of asking it. Delivered while the run loop runs; behind a
/// lock rather than the main actor, so where macOS delivers them doesn't matter.
final class NotificationLog: NSObject, Sendable {
    private struct State {
        var seenKeys: [String: Set<String>] = [:]
        /// Each one with a state, in order: its name, the state, when.
        var announcements: [(name: String, state: PlayerState, at: Date)] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
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
        let said = PlayerStateObserver.playerState(from: notification.userInfo), name = notification.name.rawValue
        state.withLock {
            $0.seenKeys[name, default: []].formUnion(keys)
            if said != .unknown { $0.announcements.append((name, said, Date())) }
        }
    }
    /// The notifications seen, with their userInfo keys.
    var seen: [String: Set<String>] { state.withLock { $0.seenKeys } }
    /// What was announced since `date`, in order.
    func announced(since date: Date) -> [(name: String, state: PlayerState, at: Date)] {
        state.withLock { $0.announcements.filter { $0.at >= date } }
    }
    /// The last state announced since `date`; a player may post each change
    /// twice, the state before, then the new one.
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
