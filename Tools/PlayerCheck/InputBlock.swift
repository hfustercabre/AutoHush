import AppKit

// MARK: - Blocking whoever runs the check

/// While a check moves the app's window and presses it (`--block-input`),
/// whoever runs it can't click, scroll or type, so nothing they do spoils a
/// drag or a trial. An active event tap where input enters the window server
/// drops their keys (modifiers, media and function keys too), clicks, drags,
/// scrolling and gestures. It lets through this tool's own events (marked
/// with `marker`), the pointer's moves (except during a drag, which they
/// would carry off), clicks on Player Check's panel (its Stop), and Escape,
/// which stops the check as Stop does. It's lifted while the check asks
/// something of them, and if the check writes nothing for `watchdog`
/// seconds; the tap goes with this process, however it ends.
/// The tap runs on a thread of its own: the main thread sleeps in waits,
/// and a tap answered there would hold up their input until macOS turned it
/// off.
final class InputBlock: @unchecked Sendable {
    /// In `kCGEventSourceUserData` of every event this tool posts.
    static let marker: Int64 = 0x50434B
    static let watchdog: TimeInterval = 60
    /// Keys and modifiers, media keys (system-defined), every mouse button's
    /// down, up and drag, the pointer's moves, scrolling, tablets and the
    /// trackpad's gestures.
    private static let types: [UInt32] = [10, 11, 12, 14, 1, 2, 3, 4, 5, 6, 7, 25, 26, 27, 22, 23, 24,
                                          18, 19, 20, 29, 30, 31, 32, 33, 34, 37]
    private static let escape: Int64 = 53

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var loop: CFRunLoop?
    private var active = false, paused = false, drag = false, escaped = false
    /// When the watchdog's minute starts: the last line the check wrote, or
    /// the block's start or resumption, whichever is later.
    private var since = Date()
    private var panels: [CGRect] = []
    /// The mouse buttons pressed on the panel: their drags and ups go through too.
    private var pressedOnPanel: Set<Int64> = []

    var isOn: Bool { lock.withLock { active } }
    /// While the check drags the window: the pointer's moves are held too.
    var dragging: Bool {
        get { lock.withLock { drag } }
        set { lock.withLock { drag = newValue } }
    }

    /// Starts blocking; false when the tap couldn't be made (it needs the
    /// Accessibility permission).
    func start() -> Bool {
        guard !isOn else { return true }
        let made = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            var mask: CGEventMask = 0
            for type in Self.types { mask |= 1 << CGEventMask(type) }
            guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                              eventsOfInterest: mask, callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                return Unmanaged<InputBlock>.fromOpaque(info).takeUnretainedValue().handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                made.signal()
                return
            }
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
            let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent(), 0.5, 0, 0) { _ in self.lookAround() }
            CFRunLoopAddTimer(loop, timer, .commonModes)
            lock.withLock {
                self.tap = tap
                self.loop = loop
                active = true
                since = Date()
            }
            made.signal()
            CFRunLoopRun()
        }
        thread.name = "input block"
        thread.start()
        made.wait()
        return isOn
    }

    /// While the check asks something of whoever runs it.
    func pause() { lock.withLock { if active { paused = true; pressedOnPanel = [] } } }
    func resume() { lock.withLock { if active { paused = false; since = Date() } } }

    /// Ends the block; whether it was on. The modifiers are then said as they
    /// are now: an app that saw one go down before the block, and not its
    /// release, would keep it held.
    @discardableResult
    func end() -> Bool {
        let (tap, loop) = lock.withLock { () -> (CFMachPort?, CFRunLoop?) in
            guard active else { return (nil, nil) }
            active = false
            defer { self.tap = nil; self.loop = nil }
            return (self.tap, self.loop)
        }
        guard let tap else { return false }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        if let loop { CFRunLoopStop(loop) }
        let source = CGEventSource(stateID: .hidSystemState)
        let modifiers = CGEvent(keyboardEventSource: source, virtualKey: 59, keyDown: false)
        modifiers?.type = .flagsChanged
        modifiers?.flags = CGEventSource.flagsState(.hidSystemState)
        modifiers?.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        modifiers?.post(tap: .cghidEventTap)
        return true
    }

    private enum Verdict { case pass, drop, escape }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = lock.withLock({ active ? tap : nil }) { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return pass }
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        let verdict: Verdict = lock.withLock {
            guard active, !paused else { return .pass }
            switch type {
            case .keyDown where event.getIntegerValueField(.keyboardEventKeycode) == Self.escape:
                if escaped { return .drop }
                escaped = true
                return .escape
            case .mouseMoved:
                return drag ? .drop : .pass
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                guard !drag, panels.contains(where: { $0.contains(event.location) }) else { return .drop }
                pressedOnPanel.insert(button)
                return .pass
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                return pressedOnPanel.remove(button) != nil ? .pass : .drop
            case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                return !drag && pressedOnPanel.contains(button) ? .pass : .drop
            default:
                return .drop
            }
        }
        switch verdict {
        case .pass: return pass
        case .drop: return nil
        case .escape:
            tell("  Escape pressed: stopping")
            // As the stop signals' handler: while the window is away (the
            // whole block), the check stops itself and puts it back.
            if !stopState.request() { stopNow(143) }
            return nil
        }
    }

    /// Every 0.5 s: where Player Check's panel is (its windows at the
    /// floating level), and whether the check still writes.
    private func lookAround() {
        let parent = getppid()
        let floating = Int(CGWindowLevelForKey(.floatingWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let frames = windows.compactMap { info -> CGRect? in
            guard (info[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) }) == parent,
                  info[kCGWindowLayer as String] as? Int == floating,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
        let silent = lock.withLock { () -> Bool in
            panels = frames
            guard active, !paused else { return false }
            return Date().timeIntervalSince(max(since, runLog.lastWrite)) > Self.watchdog
        }
        if silent, end() {
            tell("  mouse and keyboard free again: the check wrote nothing for \(Int(Self.watchdog)) s")
        }
    }

    /// A line of the report from this thread (the main one may be busy, or
    /// stuck): only a test blocks input, and its report is never quiet.
    private func tell(_ line: String) {
        log(line)
        print(line)
        fflush(nil)
    }
}

let inputBlock = InputBlock()
