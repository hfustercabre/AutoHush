import AppKit
import AutoHushKit
import ScriptablePlayers

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
/// (-600: the app quit) is asked again before the next event. Never shown
/// with --partial, as in its Permissions (L5). Nil when allowed; else the
/// error the event gets instead.
@MainActor func automationRefusal(pid: pid_t) -> NSError? {
    switch automationAnswer {
    case .allowed?: return nil
    case .denied?: return NSError(domain: NSOSStatusErrorDomain, code: Int(errAEEventNotPermitted))
    default: break
    }
    let status = AutomationPermission.check(pid: pid, ask: !partial)
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
