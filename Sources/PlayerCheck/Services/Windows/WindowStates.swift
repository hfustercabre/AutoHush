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

/// Changing an app's main window's state as a person would (reading it:
/// `AppWindows`, shared with Add an App).
@MainActor enum WindowStates {
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
                    AppWindows.infos(.optionOnScreenOnly).contains { AppWindows.number(of: $0) == number }
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
        let target: (number: Int, element: AXUIElement?)? = window.map { ($0, AppWindows.element(of: app.processIdentifier, number: $0)) }
            ?? AppWindows.main(of: app.processIdentifier).map { (AppWindows.number(of: $0.info), $0.element) }
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

    /// The modifier keys a shortcut can hold, with their key codes.
    private static let modifierKeys: [(flag: CGEventFlags, key: CGKeyCode)] = [
        (.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55),
    ]

    /// "Move right a Space" (or left) as a keyboard sends it, with the keys
    /// it's set to (Control-→ unless the user changed it): its modifiers
    /// pressed, the key with the flags it's registered with (an arrow's
    /// carry Fn and number pad: without, it does nothing), then the
    /// modifiers released, the last with no flags. The flags of posted
    /// events stay in the system's keyboard state: without the release,
    /// every later click is a Control-click, which can't drag a window.
    private static func moveSpace(right: Bool) {
        let keys = DesktopShortcuts.keys(right: right)
        let source = CGEventSource(stateID: .hidSystemState)
        let modifiers = modifierKeys.filter { keys.flags.contains($0.flag) }
        func modifier(_ index: Int, down: Bool) {
            let event = CGEvent(keyboardEventSource: source, virtualKey: modifiers[index].key, keyDown: down)
            event?.type = .flagsChanged
            // Down: it and those before; up: those before only.
            event?.flags = CGEventFlags(modifiers.prefix(down ? index + 1 : index).map(\.flag))
            post(event)
        }
        for index in modifiers.indices { modifier(index, down: true) }
        var flags = keys.flags
        if (123...126).contains(keys.keyCode) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keys.keyCode, keyDown: down)
            event?.flags = flags
            post(event)
        }
        for index in modifiers.indices.reversed() { modifier(index, down: false) }
    }

    /// Shows the main display's desktop `id` as a person would, one "Move
    /// right a Space" (or left) at a time; whether it's the current one after.
    static func showDesktop(_ id: Int) -> Bool {
        guard let all = Desktops.all(), let to = all.spaces.firstIndex(where: { $0.id == id }),
              let from = all.spaces.firstIndex(where: { $0.id == all.current }) else { return false }
        for _ in 0..<abs(to - from) {
            moveSpace(right: to > from)
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
    /// holds it), "Move right a Space" (or left) pressed, let go; the pointer goes back where
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
        guard steps != 0, let (info, _) = AppWindows.main(of: pid), let start = Desktops.of(window: AppWindows.number(of: info)) else { return false }
        let shown = activate(app, showing: AppWindows.number(of: info))
        log("  drag: \(app.localizedName ?? "the app") brought forward: \(shown); in front: \(frontName)")
        guard shown else { return false }
        Thread.sleep(forTimeInterval: 0.6)
        reveal?(true)
        defer { reveal?(false) }
        guard let element = AppWindows.element(of: pid, number: AppWindows.number(of: info)), let box = element.frame else { return false }
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
                    moveSpace(right: steps > 0)
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
        return held && Desktops.of(window: AppWindows.number(of: info)) != start
    }
}
