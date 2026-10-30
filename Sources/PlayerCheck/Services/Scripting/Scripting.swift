import AppKit
import AutoHushKit
import PlayerCheckKit
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

// MARK: - Pausing and playing it by script

/// The documents a test's pause paused, by name: its play plays them again.
@MainActor var pausedDocuments: [String] = []

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

// MARK: - Its volume, by script

/// Whether its volume can be read and set as fades need it, checked once
/// while a test has it paused (silent): its `sound volume` (pVol, 0–100),
/// else its `audio volume` (a scale of its own), set one step away and read
/// back, then put back. An app that reads back another number than it was
/// set to (one less, say) needs its reading made up for (a profile's
/// `readVolume`), or each fade restoring the volume it read loses a step. It's put back however
/// the change went: a change refused or not read back may still have taken.
@MainActor var volumeChecked = false
@MainActor func checkVolume() {
    guard !volumeChecked, let scripting, let (code, name) = volumeProperty(of: scripting) else { return }
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

/// The volume `checkVolume` checks: its `sound volume`, else its `audio
/// volume`, by code; the first code in order when it names two so, not
/// whichever the dictionary's order gives.
func volumeProperty(of scripting: Scripting) -> (code: String, name: String)? {
    for name in ["sound volume", "audio volume"] {
        if let code = scripting.properties.filter({ $0.value == name }).keys.min() { return (code, name) }
    }
    return nil
}
