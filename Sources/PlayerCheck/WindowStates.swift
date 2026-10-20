import AppKit
import AutoHushKit
import CheckedPlayers

// MARK: - Window states

/// The states a player's window can be in while AutoHush controls it, as
/// AutoHush names them (`CheckResult.WindowState`, with the report's
/// titles). A test puts the app's main window in each, in their order (the
/// fewest moves), and tries every way there, as each may work in some only
/// (an Electron player's page button worked in view, not with its window
/// full screen on another desktop).
typealias WindowState = CheckResult.WindowState

extension CheckResult.WindowState {
    /// Where Chromium treats an Electron app's page as hidden, unless the app
    /// was opened with `LaunchOption.occludedWindows`: its window fully out
    /// of view, but not minimized or hidden.
    static let outOfView: Set<WindowState> = [.covered, .otherDesktop, .otherDesktopCovered, .fullScreen]
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
    /// come with a bigger one it doesn't: an Apple player's), else its biggest.
    static func main(of pid: pid_t) -> (info: Info, element: AXUIElement?)? {
        let known = windowElements(of: pid)
        let standard = standardWindows(in: known)
        let candidates = infos(.optionAll).filter { owner(of: $0) == pid && isOrdinary($0, standard: standard) }
        guard !candidates.isEmpty else { return nil }
        func area(_ info: Info) -> CGFloat { frame(of: info).width * frame(of: info).height }
        let numbers = Set(known.map(\.number))
        guard let info = candidates.filter({ numbers.contains(number(of: $0)) }).max(by: { area($0) < area($1) })
                ?? candidates.max(by: { area($0) < area($1) }) else { return nil }
        return (info, known.first { $0.number == number(of: info) }?.element)
    }

    /// Its window in front among its ordinary ones on screen (the list goes
    /// front to back), when it has one.
    static func frontWindow(of pid: pid_t) -> Int? {
        let standard = standardWindows(in: windowElements(of: pid))
        return infos(.optionOnScreenOnly).first { owner(of: $0) == pid && isOrdinary($0, standard: standard) }.map(number(of:))
    }

    /// An ordinary window: a document window's layer, and either a standard
    /// window to Accessibility, whatever its height (a movie player's for
    /// sound alone can be about 130 points tall), or at least 200 points tall
    /// (not a strip or a helper).
    static func isOrdinary(_ info: Info, standard: Set<Int>) -> Bool {
        isOrdinary(layer: info[kCGWindowLayer as String] as? Int, height: frame(of: info).height, isStandard: standard.contains(number(of: info)))
    }

    /// `isOrdinary`'s rule, on what it reads of the window.
    nonisolated static func isOrdinary(layer: Int?, height: CGFloat, isStandard: Bool) -> Bool {
        layer == 0 && (isStandard || height >= 200)
    }

    /// The numbers of the windows Accessibility calls standard ones, and of
    /// the minimized ones (macOS 14.4 calls a minimized window a dialog).
    static func standardWindows(in known: [(number: Int, element: AXUIElement)]) -> Set<Int> {
        Set(known.filter {
            $0.element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole || $0.element.value(kAXMinimizedAttribute) as? Bool == true
        }.map(\.number))
    }

    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindow = PrivateSymbol.function("_AXUIElementGetWindow", as: GetWindow.self)

    /// The app's windows Accessibility knows, with their numbers: this
    /// desktop's (minimized ones too) and every other's (`AccessibilityWindows`),
    /// each read waiting 1 s.
    static func windowElements(of pid: pid_t) -> [(number: Int, element: AXUIElement)] {
        guard let getWindow else { return [] }
        let app = AXUIElement.application(pid, timeout: 1)
        var found: [(number: Int, element: AXUIElement)] = []
        for element in app.elements(kAXWindowsAttribute, timeout: 1) + (AccessibilityWindows.windows(ofProcess: pid) ?? []) {
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
        return isCovered(box: frame(of: info), above: windowsAbove(info).map(\.frame))
    }

    /// `isCovered`'s rule: whether `above` holds every point of a 9×9 grid
    /// over `box`, edges included, a window within half a point counting.
    nonisolated static func isCovered(box: CGRect, above: [CGRect]) -> Bool {
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
    /// desktop's order (an Electron player's, the front window there, read as covered).
    /// A closed window an app keeps counts as none.
    static func state(of app: NSRunningApplication) -> WindowState? {
        let pid = app.processIdentifier
        let appElement = AXUIElement.application(pid, timeout: 1)
        if appElement.value(kAXHiddenAttribute) as? Bool == true { return .hidden }
        guard let (info, element) = main(of: pid) else { return nil }
        if element?.value(kAXMinimizedAttribute) as? Bool == true { return .minimized }
        if element?.value("AXFullScreen") as? Bool == true { return .fullScreen }
        if info[kCGWindowIsOnscreen as String] as? Bool == true { return isCovered(info) ? .covered : .visible }
        // Off screen on this very desktop: closed, as an Electron app keeps a
        // closed window (a player's, playing on), or ordered out.
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
    private static let getFrontProcess = PrivateSymbol.function("_SLPSGetFrontProcess", as: GetFrontProcess.self)
    private static let setFrontProcess = PrivateSymbol.function("_SLPSSetFrontProcessWithOptions", as: SetFrontProcess.self)
    private static let processForPID = PrivateSymbol.function("GetProcessForPID", as: ProcessForPID.self)
    private static let pidForProcess = PrivateSymbol.function("GetProcessPID", as: PIDForProcess.self)

    /// The app in front now, by name, for the log.
    static var frontName: String {
        frontPID().flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "?"
    }

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
    /// may play again then (one did).
    @discardableResult
    static func activate(_ app: NSRunningApplication, showing window: Int? = nil) -> Bool {
        func there(within seconds: Double) -> Bool {
            Polling.wait(seconds: seconds, every: 0.1, lookingLate: false) {
                let front = frontPID() == app.processIdentifier
                let shown = window.map { number in
                    infos(.optionOnScreenOnly).contains { WindowStates.number(of: $0) == number }
                } ?? true
                return front && shown
            }
        }
        // Without Accessibility, reading its windows would make macOS ask for
        // it there and then (Add an App opens the app with its launch option
        // before its Allow step): brought forward as `open` does.
        guard AXIsProcessTrusted() else {
            if let url = app.bundleURL { bringForward(url) }
            return there(within: 2.5)
        }
        // The process forward, then its window above the others (SkyLight's
        // call alone left an Electron player's window under Player Check's).
        let target: (number: Int, element: AXUIElement?)? = window.map { ($0, element(of: app.processIdentifier, number: $0)) }
            ?? main(of: app.processIdentifier).map { (number(of: $0.info), $0.element) }
        if let target, setFront(app.processIdentifier, window: target.number) {
            if let element = target.element { AXUIElementPerformAction(element, kAXRaiseAction as CFString) }
            if there(within: 2) { return true }
        }
        if let url = app.bundleURL { bringForward(url) }
        // `open` brings its windows forward in their own order: the one asked
        // for on top (AutoHush's Add an App above its Settings).
        if window != nil, let element = target?.element { AXUIElementPerformAction(element, kAXRaiseAction as CFString) }
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

    // MARK: Dragging it to another desktop

    /// Marked as this tool's, which `InputBlock` lets through.
    private static func post(_ event: CGEvent?) {
        event?.setIntegerValueField(.eventSourceUserData, value: InputBlock.marker)
        event?.post(tap: .cghidEventTap)
        usleep(40_000)
    }
    /// With no modifiers: made from the system's state, it would carry one
    /// held on the keyboard (a Control-click can't drag a window).
    private static func mouse(_ type: CGEventType, at point: CGPoint) {
        let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: point,
                            mouseButton: .left)
        event?.flags = []
        post(event)
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
        return Polling.wait(seconds: 2, every: 0.1, until: { Desktops.all()?.current == id })
    }

    /// Where the window can be held to drag it: right of its zoom button (a
    /// title bar), then along its top bar, at spots that aren't controls. An
    /// Electron app's top bar can be dragged only where its page marks it so,
    /// which Accessibility can't tell (one player's: right of its search field),
    /// so each spot is tried in turn.
    private static func grips(_ element: AXUIElement, _ box: CGRect) -> [CGPoint] {
        var points: [CGPoint] = []
        if let zoom = element.element(kAXZoomButtonAttribute, timeout: 1)?.frame, zoom.width > 0 {
            points.append(CGPoint(x: zoom.maxX + 16, y: zoom.midY))
        }
        for y in [box.minY + 14, box.minY + 24] {
            var x = box.maxX - 40
            while x > box.minX + 80 {
                points.append(CGPoint(x: x, y: y))
                x -= 60
            }
        }
        // A timeout set on the system-wide element would be every element's
        // in this process (Apple's header): its hit tests keep macOS's own;
        // what they find waits 1 s.
        let system = AXUIElementCreateSystemWide()
        let controls: Set<String> = [kAXButtonRole, kAXTextFieldRole, "AXSearchField", "AXLink", kAXCheckBoxRole, kAXPopUpButtonRole,
                                     kAXMenuButtonRole, kAXRadioButtonRole, kAXSliderRole, kAXComboBoxRole, kAXTextAreaRole, kAXImageRole]
        return points.filter { point in
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit else { return true }
            hit.waiting(1)
            return !controls.contains(hit.text(kAXRoleAttribute)) && !hit.actionNames.contains(kAXPressAction)
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
        // Once more when no spot held it (a Safari web app, just shown
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
        log("  drag: \(app.localizedName ?? "the app") brought forward: \(shown); in front: \(frontName)")
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
        inputBlock.dragging = true
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
                // can sit short of its place (4 pt, measured): the pointer goes on
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
        inputBlock.dragging = false
        Thread.sleep(forTimeInterval: 0.4)
        return held && Desktops.of(window: number(of: info)) != start
    }
}
