import AppKit
import AutoHushKit

// MARK: - Window states

/// The states a player's window can be in while AutoHush controls it. A test
/// puts the app's main window in each, in this order (the fewest moves), and
/// tries every way there, as each may work in some only (Deezer's page
/// button worked in view, not with its window full screen on another desktop).
enum WindowState: CaseIterable {
    case visible, covered, otherDesktop, otherDesktopCovered, fullScreen, minimized, hidden
    /// As the report names it: the Player Check app reads these.
    var title: String {
        switch self {
        case .visible: "visible"
        case .covered: "covered"
        case .otherDesktop: "on another desktop"
        case .otherDesktopCovered: "covered on another desktop"
        case .fullScreen: "full screen"
        case .minimized: "minimized"
        case .hidden: "hidden"
        }
    }
    /// Where Chromium treats an Electron app's page as hidden, unless the app
    /// was opened with `LaunchOption.occludedWindows`: its window fully out
    /// of view, but not minimized or hidden.
    static let outOfView: Set<WindowState> = [.covered, .otherDesktop, .otherDesktopCovered, .fullScreen]
}

/// The launch option an Electron app needs for its page to take presses
/// while its window is covered or on another desktop. Without it, Chromium
/// treats a page whose window is fully out of view as hidden and ignores
/// presses on it; with it, Deezer's worked covered, on another desktop and
/// full screen there. A CEF app (Spotify) took presses covered without it,
/// so it's Electron's only.
enum LaunchOption {
    static let occludedWindows = "--disable-backgrounding-occluded-windows"

    /// The option the app needs, by the framework in its bundle.
    static func needed(by url: URL) -> String? {
        if case .electron? = HiddenInterface.of(url) { return occludedWindows }
        return nil
    }

    /// A process's launch arguments, its own path first, as `ps` reads them
    /// (`KERN_PROCARGS2`: processes of the same user).
    static func arguments(of pid: pid_t) -> [String] {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 4 else { return [] }
        let count = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        // After the count: the executable's path, NULs, then the arguments.
        var index = 4
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var found: [String] = []
        while found.count < count, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            found.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return found
    }

    /// What `openApplication` answered, from the queue it answers on.
    private final class Opened: @unchecked Sendable {
        var app: NSRunningApplication?
        var error: Error?
    }

    /// Quits the app as a person would (never by force: it's given 15 s), then
    /// opens it again with `option`, in the background: an app that comes
    /// forward by itself once its window shows (Deezer does) goes behind the
    /// app that was in front again. Says how it went (`tell`).
    @MainActor static func relaunch(_ app: NSRunningApplication?, url: URL, with option: String, tell: (String) -> Void) -> Bool {
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let front = WindowStates.frontPID().flatMap { NSRunningApplication(processIdentifier: $0) }
        if let app {
            _ = app.terminate()
            let deadline = Date().addingTimeInterval(15)
            while !app.isTerminated, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
            guard app.isTerminated else {
                tell("\(name) didn't quit within 15 s (it may be asking something): quit it yourself, then try again.")
                return false
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [option]
        configuration.activates = false
        let opened = Opened()
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { @Sendable app, error in // on another thread
            opened.app = app
            opened.error = error
            done.signal()
        }
        guard done.wait(timeout: .now() + 30) == .success, let new = opened.app else {
            tell("Couldn't open \(name) again: \(opened.error?.localizedDescription ?? "macOS didn't answer").")
            return false
        }
        // It may come forward a few seconds after its window shows (Deezer's
        // once its page loaded): watched for 12 s, sent back each time.
        if let front, front.processIdentifier != app?.processIdentifier {
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                if WindowStates.frontPID() == new.processIdentifier {
                    Thread.sleep(forTimeInterval: 0.3)
                    WindowStates.activate(front)
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        tell("\(app == nil ? "Opened" : "Relaunched") \(name) with \(option) (pid \(new.processIdentifier)).")
        return true
    }
}

/// --launch-option, --relaunch and --window-state <app>, for the Player
/// Check app: whether the app needs a launch option and runs with it
/// ("<option, or nothing>\t<yes|no|not running>"), quitting it and opening
/// it again with that option, and the state its window is in now (one of
/// `WindowState`'s titles, "no window" or "not running"), for its Play and
/// Pause by the way that worked in that state.
enum AppQuery: String { case launchOption = "--launch-option", relaunch = "--relaunch", windowState = "--window-state" }

@MainActor func answer(_ query: AppQuery) -> Never {
    guard CommandLine.arguments.count > 2, let url = findApp(CommandLine.arguments[2]), let id = Bundle(url: url)?.bundleIdentifier else {
        print("no app found")
        exit(1)
    }
    let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first
    switch query {
    case .launchOption:
        let needed = LaunchOption.needed(by: url)
        print([needed ?? "", needed == nil ? "" : app.map { LaunchOption.arguments(of: $0.processIdentifier).contains(needed!) ? "yes" : "no" }
                                                ?? "not running"].joined(separator: "\t"))
        exit(0)
    case .relaunch:
        // It quits and opens the app, so it's logged as checks and presses
        // are; the two questions aren't (Player Check asks them often).
        runLog.start(app: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), doing: "relaunch")
        let tell = { (line: String) in
            log(line)
            print(line)
        }
        guard let needed = LaunchOption.needed(by: url) else {
            tell("It needs no launch option.")
            exit(1)
        }
        exit(LaunchOption.relaunch(app, url: url, with: needed, tell: tell) ? 0 : 1)
    case .windowState:
        print(app.map { WindowStates.state(of: $0)?.title ?? "no window" } ?? "not running")
        exit(0)
    }
}

/// A function of macOS's private frameworks by one of its names, as window
/// managers resolve them at run time; nil when gone.
func privateSymbol<T>(_ names: String..., as type: T.Type) -> T? {
    for name in names {
        if let found = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) { return unsafeBitCast(found, to: type) }
    }
    return nil
}

/// macOS's desktops (Spaces), read through SkyLight's read-only calls, as
/// window managers read them. Only the main display's.
enum Desktops {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let connection = privateSymbol("SLSMainConnectionID", "CGSMainConnectionID", as: MainConnection.self)
    private static let displaySpaces = privateSymbol("SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces", as: CopyDisplaySpaces.self)
    private static let spacesForWindows = privateSymbol("SLSCopySpacesForWindows", "CGSCopySpacesForWindows", as: CopySpacesForWindows.self)

    /// The main display's desktops in order (full screen apps' among them),
    /// and the current one.
    static func all() -> (spaces: [(id: Int, isFullScreen: Bool)], current: Int)? {
        guard let connection, let displaySpaces,
              let main = (displaySpaces(connection())?.takeRetainedValue() as? [[String: Any]])?.first else { return nil }
        func id(_ space: [String: Any]?) -> Int { (space?["ManagedSpaceID"] as? Int) ?? (space?["id64"] as? Int) ?? 0 }
        let listed = main["Spaces"] as? [[String: Any]] ?? []
        let spaces: [(id: Int, isFullScreen: Bool)] = listed.map { space in (id: id(space), isFullScreen: space["type"] as? Int == 4) }
        guard !spaces.isEmpty else { return nil }
        return (spaces, id(main["Current Space"] as? [String: Any]))
    }

    /// The desktop a window is on.
    static func of(window: Int) -> Int? {
        guard let connection, let spacesForWindows,
              let spaces = spacesForWindows(connection(), 7, [window] as CFArray)?.takeRetainedValue() as? [Int] else { return nil }
        return spaces.first
    }

    /// Where a desktop is in the main display's order.
    static func index(of id: Int) -> Int? { all()?.spaces.firstIndex { $0.id == id } }
}

/// Reading an app's main window's state, and changing it as a person would.
@MainActor enum WindowStates {
    typealias Info = [String: Any]
    static func infos(_ option: CGWindowListOption) -> [Info] {
        CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [Info] ?? []
    }
    static func frame(of info: Info) -> CGRect {
        (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
    }
    static func number(of info: Info) -> Int { info[kCGWindowNumber as String] as? Int ?? 0 }
    static func owner(of info: Info) -> pid_t { info[kCGWindowOwnerPID as String] as? pid_t ?? 0 }

    /// The app's main window, and its Accessibility element when it can be
    /// reached, from one look at its windows (the search for windows on
    /// other desktops takes about 70 ms, up to 1 s): its biggest ordinary one
    /// that Accessibility knows, wherever it is (a full screen window may
    /// come with a bigger one it doesn't: Music's), else its biggest.
    static func main(of pid: pid_t) -> (info: Info, element: AXUIElement?)? {
        let candidates = infos(.optionAll).filter {
            owner(of: $0) == pid && $0[kCGWindowLayer as String] as? Int == 0 && frame(of: $0).height >= 200
        }
        guard !candidates.isEmpty else { return nil }
        func area(_ info: Info) -> CGFloat { frame(of: info).width * frame(of: info).height }
        let known = windowElements(of: pid)
        let numbers = Set(known.map(\.number))
        guard let info = candidates.filter({ numbers.contains(number(of: $0)) }).max(by: { area($0) < area($1) })
                ?? candidates.max(by: { area($0) < area($1) }) else { return nil }
        return (info, known.first { $0.number == number(of: info) }?.element)
    }

    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindow = privateSymbol("_AXUIElementGetWindow", as: GetWindow.self)

    /// The app's windows Accessibility knows, with their numbers: this
    /// desktop's (minimized ones too) and every other's (`AccessibilityWindows`).
    static func windowElements(of pid: pid_t) -> [(number: Int, element: AXUIElement)] {
        guard let getWindow else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var found: [(number: Int, element: AXUIElement)] = []
        for element in app.elements(kAXWindowsAttribute) + (AccessibilityWindows.windows(ofProcess: pid) ?? []) {
            var id: CGWindowID = 0
            if getWindow(element, &id) == .success, !found.contains(where: { $0.number == Int(id) }) { found.append((Int(id), element)) }
        }
        return found
    }

    /// A window's Accessibility element.
    static func element(of pid: pid_t, number: Int) -> AXUIElement? {
        windowElements(of: pid).first { $0.number == number }?.element
    }

    /// The windows on screen above `info` that overlap it, front first, with their apps.
    static func windowsAbove(_ info: Info) -> [(pid: pid_t, window: Int, frame: CGRect)] {
        let list = infos(.optionOnScreenOnly)
        guard let index = list.firstIndex(where: { number(of: $0) == number(of: info) }) else { return [] }
        let box = frame(of: info)
        return list[..<index].filter { other in
            other[kCGWindowLayer as String] as? Int == 0 && (other[kCGWindowAlpha as String] as? Double ?? 1) > 0
                && frame(of: other).insetBy(dx: -0.5, dy: -0.5).intersects(box)
        }.map { (owner(of: $0), number(of: $0), frame(of: $0)) }
    }

    /// Whether the windows on screen above it cover every point of a grid over it.
    static func isCovered(_ info: Info) -> Bool {
        guard infos(.optionOnScreenOnly).contains(where: { number(of: $0) == number(of: info) }) else { return false }
        let above = windowsAbove(info).map(\.frame)
        let box = frame(of: info)
        for row in 0...8 {
            for column in 0...8 {
                let point = CGPoint(x: box.minX + box.width * CGFloat(column) / 8, y: box.minY + box.height * CGFloat(row) / 8)
                if !above.contains(where: { $0.insetBy(dx: -0.5, dy: -0.5).contains(point) }) { return false }
            }
        }
        return true
    }

    /// The state its main window is in; nil without one. Hidden is the app's
    /// (Accessibility answers it as it is now); then minimized and full
    /// screen, the window's; else where the window server has it. On another
    /// desktop, never covered there: the window list doesn't keep another
    /// desktop's order (Deezer's, the front window there, read as covered).
    /// A closed window an app keeps counts as none.
    static func state(of app: NSRunningApplication) -> WindowState? {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1)
        if appElement.value(kAXHiddenAttribute) as? Bool == true { return .hidden }
        guard let (info, element) = main(of: pid) else { return nil }
        if element?.value(kAXMinimizedAttribute) as? Bool == true { return .minimized }
        if element?.value("AXFullScreen") as? Bool == true { return .fullScreen }
        if info[kCGWindowIsOnscreen as String] as? Bool == true { return isCovered(info) ? .covered : .visible }
        // Off screen on this very desktop: closed, as an Electron app keeps a
        // closed window (Deezer's, playing on), or ordered out.
        if let desktop = Desktops.of(window: number(of: info)), desktop == Desktops.all()?.current { return nil }
        return .otherDesktop
    }

    // SkyLight's front process, as window switchers (AltTab) read and set it:
    // from a process in the background, Accessibility's AXFrontmost and
    // NSRunningApplication.activate() answer success and change nothing, and
    // NSWorkspace's front app lags seconds in the process that changed it.
    private typealias GetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
    private typealias SetFrontProcess = @convention(c) (UnsafePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
    private typealias ProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
    private typealias PIDForProcess = @convention(c) (UnsafePointer<ProcessSerialNumber>, UnsafeMutablePointer<pid_t>) -> Int32
    private static let getFrontProcess = privateSymbol("_SLPSGetFrontProcess", as: GetFrontProcess.self)
    private static let setFrontProcess = privateSymbol("_SLPSSetFrontProcessWithOptions", as: SetFrontProcess.self)
    private static let processForPID = privateSymbol("GetProcessForPID", as: ProcessForPID.self)
    private static let pidForProcess = privateSymbol("GetProcessPID", as: PIDForProcess.self)

    /// The app in front now.
    static func frontPID() -> pid_t? {
        var process = ProcessSerialNumber(), pid: pid_t = 0
        if let getFrontProcess, let pidForProcess, getFrontProcess(&process) == 0, pidForProcess(&process, &pid) == 0, pid > 0 { return pid }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    /// Brings the process forward with `window` (its desktop shown), as a
    /// person's click would ("user generated"): whether it was asked.
    private static func setFront(_ pid: pid_t, window: Int) -> Bool {
        var process = ProcessSerialNumber()
        guard let setFrontProcess, let processForPID, processForPID(pid, &process) == 0 else { return false }
        return setFrontProcess(&process, UInt32(window), 0x200) == 0
    }

    /// Brings an app to the front, and to its window's desktop (`window`, when
    /// it must be on screen after; else its main window): through SkyLight,
    /// as window switchers do; else as `open` does, last, as a Safari web app
    /// may play again then (SoundCloud's did).
    @discardableResult
    static func activate(_ app: NSRunningApplication, showing window: Int? = nil) -> Bool {
        func there(within seconds: Double) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            repeat {
                let front = frontPID() == app.processIdentifier
                let shown = window.map { number in
                    infos(.optionOnScreenOnly).contains { WindowStates.number(of: $0) == number }
                } ?? true
                if front && shown { return true }
                Thread.sleep(forTimeInterval: 0.1)
            } while Date() < deadline
            return false
        }
        // The process forward, then its window above the others (SkyLight's
        // call alone left Deezer's window under Player Check's).
        let target: (number: Int, element: AXUIElement?)? = window.map { ($0, element(of: app.processIdentifier, number: $0)) }
            ?? main(of: app.processIdentifier).map { (number(of: $0.info), $0.element) }
        if let target, setFront(app.processIdentifier, window: target.number) {
            if let element = target.element { AXUIElementPerformAction(element, kAXRaiseAction as CFString) }
            if there(within: 2) { return true }
        }
        if let url = app.bundleURL { bringForward(url) }
        return there(within: 2.5)
    }

    static func set(_ element: AXUIElement, _ attribute: String, _ on: Bool) {
        AXUIElementSetAttributeValue(element, attribute as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
    }

    static func setFrame(_ element: AXUIElement, _ frame: CGRect, size: Bool = true) {
        var origin = frame.origin, extent = frame.size
        if let position = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        }
        if size, let value = AXValueCreate(.cgSize, &extent) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
    }

    /// Waits up to `seconds` for `done`.
    static func wait(_ seconds: Double, until done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !done() {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return true
    }

    // MARK: Dragging it to another desktop

    private static func post(_ event: CGEvent?) {
        event?.post(tap: .cghidEventTap)
        usleep(40_000)
    }
    private static func mouse(_ type: CGEventType, at point: CGPoint) {
        post(CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: point,
                     mouseButton: .left))
    }

    /// Control-→ (or ←) as a keyboard sends it: Control pressed, the arrow
    /// with the Fn and number-pad flags arrows carry (macOS's desktop
    /// shortcuts are registered with them: without, it does nothing), then
    /// Control released with no flags. The flags of posted events stay in the
    /// system's keyboard state: without the release, every later click is a
    /// Control-click, which can't drag a window.
    private static func controlArrow(right: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        func control(down: Bool) {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 59, keyDown: down)
            event?.type = .flagsChanged
            event?.flags = down ? .maskControl : []
            post(event)
        }
        control(down: true)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: right ? 124 : 123, keyDown: down)
            event?.flags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
            post(event)
        }
        control(down: false)
    }

    /// Shows the main display's desktop `id` as a person would, one Control-→
    /// or ← at a time; whether it's the current one after.
    static func showDesktop(_ id: Int) -> Bool {
        guard let all = Desktops.all(), let to = all.spaces.firstIndex(where: { $0.id == id }),
              let from = all.spaces.firstIndex(where: { $0.id == all.current }) else { return false }
        for _ in 0..<abs(to - from) {
            controlArrow(right: to > from)
            Thread.sleep(forTimeInterval: 0.9)
        }
        return wait(2, until: { Desktops.all()?.current == id })
    }

    /// Where the window can be held to drag it: right of its zoom button (a
    /// title bar), then along its top bar, at spots that aren't controls. An
    /// Electron app's top bar can be dragged only where its page marks it so,
    /// which Accessibility can't tell (Deezer's: right of its search field),
    /// so each spot is tried in turn.
    private static func grips(_ element: AXUIElement, _ box: CGRect) -> [CGPoint] {
        var points: [CGPoint] = []
        if let zoom = element.element(kAXZoomButtonAttribute)?.frame, zoom.width > 0 {
            points.append(CGPoint(x: zoom.maxX + 16, y: zoom.midY))
        }
        for y in [box.minY + 14, box.minY + 24] {
            var x = box.maxX - 40
            while x > box.minX + 80 {
                points.append(CGPoint(x: x, y: y))
                x -= 60
            }
        }
        let system = AXUIElementCreateSystemWide()
        let controls: Set<String> = [kAXButtonRole, kAXTextFieldRole, "AXSearchField", "AXLink", kAXCheckBoxRole, kAXPopUpButtonRole,
                                     kAXMenuButtonRole, kAXRadioButtonRole, kAXSliderRole, kAXComboBoxRole, kAXTextAreaRole, kAXImageRole]
        return points.filter { point in
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit else { return true }
            return !controls.contains(hit.text(kAXRoleAttribute)) && !hit.actions.contains(kAXPressAction)
        }
    }

    /// Drags the app's main window `steps` desktops right (left when
    /// negative), as a person would: it's brought forward, held at a spot of
    /// its top bar (a small drag towards the screen's middle shows the spot
    /// holds it), Control-→ or ← pressed, let go; the pointer goes back where
    /// it was. Once held, the window is dragged back to where it started before
    /// the desktop changes, so it lands in its place.
    /// `reveal` shows its page to Accessibility while it's in view (true), so
    /// the spots tried aren't its page's buttons, and hides it again after
    /// (false). Whether it got there.
    static func move(_ app: NSRunningApplication, desktops steps: Int, reveal: ((Bool) -> Void)? = nil) -> Bool {
        // Once more when no spot held it (SoundCloud's web app, just shown
        // again after hidden, held nowhere once).
        for attempt in 1...2 {
            if moveOnce(app, desktops: steps, reveal: reveal) { return true }
            log("  drag: attempt \(attempt) didn't take it there")
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    private static func moveOnce(_ app: NSRunningApplication, desktops steps: Int, reveal: ((Bool) -> Void)?) -> Bool {
        let pid = app.processIdentifier
        guard steps != 0, let (info, _) = main(of: pid), let start = Desktops.of(window: number(of: info)) else { return false }
        let shown = activate(app, showing: number(of: info))
        log("  drag: \(app.localizedName ?? "the app") brought forward: \(shown); in front: "
            + (frontPID().flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "?"))
        guard shown else { return false }
        Thread.sleep(forTimeInterval: 0.6)
        reveal?(true)
        defer { reveal?(false) }
        guard let element = element(of: pid, number: number(of: info)), let box = element.frame else { return false }
        let pointer = CGEvent(source: nil)?.location ?? .zero
        let direction: CGFloat = box.midX > (NSScreen.screens.first?.frame.midX ?? 0) ? -1 : 1
        var held = false
        let spots = grips(element, box)
        log(String(format: "  drag: window at %.0f,%.0f, %d spots to try", box.minX, box.minY, spots.count))
        for grip in spots {
            mouse(.mouseMoved, at: grip)
            mouse(.leftMouseDown, at: grip)
            for step in 1...3 { mouse(.leftMouseDragged, at: CGPoint(x: grip.x + direction * CGFloat(step) * 4, y: grip.y)) }
            usleep(150_000)
            held = element.frame.map { $0.minX != box.minX } ?? false
            log(String(format: "  drag: %@ at %.0f,%.0f", held ? "held" : "not held", grip.x, grip.y))
            if held {
                // Back where it started, held still, then to the other desktop.
                for step in [2, 1, 0] { mouse(.leftMouseDragged, at: CGPoint(x: grip.x + direction * CGFloat(step) * 4, y: grip.y)) }
                usleep(150_000)
                // A drag's first points don't move the window (macOS waits for
                // the pointer to go a little way first), so back at the grip it
                // can sit short of its place (VLC's, 4 pt): the pointer goes on
                // by what's missing until it's there.
                var at = grip
                for _ in 0..<3 {
                    guard let now = element.frame, now.origin != box.origin else { break }
                    at = CGPoint(x: at.x + box.minX - now.minX, y: at.y + box.minY - now.minY)
                    mouse(.leftMouseDragged, at: at)
                    usleep(150_000)
                }
                log(String(format: "  drag: held in place at %.0f,%.0f", element.frame?.minX ?? -1, element.frame?.minY ?? -1))
                for _ in 0..<abs(steps) {
                    controlArrow(right: steps > 0)
                    Thread.sleep(forTimeInterval: 0.9)
                }
                mouse(.leftMouseUp, at: at)
                break
            }
            mouse(.leftMouseUp, at: CGPoint(x: grip.x + direction * 12, y: grip.y))
        }
        CGWarpMouseCursorPosition(pointer)
        CGAssociateMouseAndMouseCursorPosition(1)
        Thread.sleep(forTimeInterval: 0.4)
        return held && Desktops.of(window: number(of: info)) != start
    }
}

/// An opaque window over the app's, from this tool: another window covering
/// it, as Chromium counts one (Deezer's page took no presses under it, as
/// under any window). Made while another desktop is current, it lands there.
@MainActor final class CoverWindow {
    private var window: NSWindow?
    var number: Int? { window.map { $0.windowNumber } }

    func show(over box: CGRect, naming name: String) {
        remove()
        NSApplication.shared.setActivationPolicy(.accessory)
        let area = box.insetBy(dx: -20, dy: -20)
        let top = NSScreen.screens.first?.frame.height ?? 0
        let made = NSWindow(contentRect: NSRect(x: area.minX, y: top - area.maxY, width: area.width, height: area.height),
                            styleMask: .borderless, backing: .buffered, defer: false)
        made.isOpaque = true
        made.backgroundColor = .windowBackgroundColor
        made.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "Player Check covers \(name) here for its test")
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.frame = NSRect(x: 24, y: area.height / 2 - 12, width: area.width - 48, height: 24)
        made.contentView?.addSubview(label)
        made.orderFrontRegardless()
        made.display()
        window = made
        settle()
    }

    /// AppKit shows (or takes away) the window once its transaction is
    /// committed, which happens as the run loop turns: this tool's waits
    /// don't turn it.
    private func settle() {
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }

    func remove() {
        guard window != nil else { return }
        window?.orderOut(nil)
        window = nil
        settle()
    }
}
