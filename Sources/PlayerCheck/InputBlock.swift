import AppKit
import PlayerCheckKit

// MARK: - Blocking whoever runs the check

/// While a check moves the app's window and presses it (`--block-input`),
/// whoever runs it can't click, scroll or type, so nothing they do spoils a
/// drag or a trial. An active event tap where input enters the window server
/// drops their keys (modifiers, media and function keys too), clicks, drags,
/// scrolling and gestures. It lets through this tool's own events (marked
/// with `marker`), the pointer's moves (except during a drag, which they
/// would carry off), clicks on the check's panel (`CheckPanelWindows`: its
/// Stop; during a drag, a click there is taken as Stop, as it can't reach
/// the panel without letting go of the window), and Escape, which stops the
/// check as Stop does. It's lifted while the check asks something of them;
/// if the check writes nothing for `watchdog` seconds (the block's own lines
/// don't count), or doesn't reach its next step within `stopWait` of a stop,
/// it's lifted and the check stops at its next step. The tap goes with this
/// process, however it ends.
/// The tap runs on a thread of its own: the main thread sleeps in waits,
/// and a tap answered there would hold up their input until macOS turned it
/// off.
final class InputBlock: @unchecked Sendable {
    /// In `kCGEventSourceUserData` of every event this tool posts.
    static let marker: Int64 = 0x50434B
    static let watchdog: TimeInterval = 60
    /// How long a stop (Escape, Stop) waits for the check's next step before
    /// the mouse and keyboard are freed anyway: a step can wait on a slow app.
    static let stopWait: TimeInterval = 4
    /// Keys and modifiers, media keys (system-defined), every mouse button's
    /// down, up and drag, the pointer's moves, scrolling, tablets and the
    /// trackpad's gestures.
    private static let types: [UInt32] = [10, 11, 12, 14, 1, 2, 3, 4, 5, 6, 7, 25, 26, 27, 22, 23, 24,
                                          18, 19, 20, 29, 30, 31, 32, 33, 34, 37]
    private static let escape: Int64 = 53

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var loop: CFRunLoop?
    private var active = false, paused = false, drag = false, stopAsked = false
    /// Set by `end`: the thread's timer stops its run loop, in case `end`
    /// came before the loop ran.
    private var ended = false
    /// When the watchdog's minute starts: the last line the check wrote, or
    /// the block's start or resumption, whichever is later.
    private var since = Date()
    private var panels: [CGRect] = []
    /// The mouse buttons pressed on the panel: their drags and ups go through too.
    private var pressedOnPanel: Set<Int64> = []

    var isOn: Bool { lock.withLock { active } }
    /// While the check drags the window: the pointer's moves are held too,
    /// and a button held on the panel since before doesn't get its release.
    var dragging: Bool {
        get { lock.withLock { drag } }
        set { lock.withLock { drag = newValue; if newValue { pressedOnPanel = [] } } }
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
            let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent(), 0.5, 0, 0) { _ in
                guard !self.lock.withLock({ self.ended }) else { return CFRunLoopStop(CFRunLoopGetCurrent()) }
                self.lookAround()
            }
            CFRunLoopAddTimer(loop, timer, .commonModes)
            lock.withLock {
                self.tap = tap
                self.loop = loop
                active = true
                ended = false
                since = Date()
            }
            // Said once the loop runs, so an `end` right after `start` stops it.
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { made.signal() }
            CFRunLoopWakeUp(loop)
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
            ended = true
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

    private enum Verdict { case pass, drop, stop(String) }

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
                if stopAsked { return .drop }
                stopAsked = true
                return .stop("  Escape pressed: stopping")
            case .mouseMoved:
                return drag ? .drop : .pass
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                guard panels.contains(where: { $0.contains(event.location) }) else { return .drop }
                if drag {
                    if stopAsked { return .drop }
                    stopAsked = true
                    return .stop("  the panel clicked during a drag: stopping")
                }
                pressedOnPanel.insert(button)
                return .pass
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                return !drag && pressedOnPanel.remove(button) != nil ? .pass : .drop
            case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                return !drag && pressedOnPanel.contains(button) ? .pass : .drop
            default:
                return .drop
            }
        }
        switch verdict {
        case .pass: return pass
        case .drop: return nil
        case .stop(let line):
            tell(line)
            // As the stop signals' handler: while the window is away (the
            // whole block), the check stops itself and puts it back.
            if !stopState.request() { stopNow(143) }
            return nil
        }
    }

    /// Every 0.5 s: where the check's panel is (`CheckPanelWindows`), whether
    /// the check still writes, and whether a stop waits too long for it.
    private func lookAround() {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &displays, &count)
        let screens = displays.prefix(Int(count)).map(CGDisplayBounds)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let frames = CheckPanelWindows.frames(in: windows, ownedBy: getppid(), screens: screens)
        let stopSince = stopState.since
        let why = lock.withLock { () -> String? in
            panels = frames
            guard active else { return nil }
            if let stopSince, Date().timeIntervalSince(stopSince) > Self.stopWait {
                return "the check is stopping, at its next step"
            }
            guard !paused else { return nil }
            return Date().timeIntervalSince(max(since, runLog.lastWrite)) > Self.watchdog
                ? "the check wrote nothing for \(Int(Self.watchdog)) s, so it stops at its next step" : nil
        }
        if let why, end() {
            tell("  mouse and keyboard free again: \(why)")
            // Back, it would drag the window with their input free: it stops (and puts it back) instead.
            _ = stopState.request()
        }
    }

    /// A line of the report from this thread (the main one may be busy, or
    /// stuck): only a test blocks input, and its report is never quiet. It
    /// isn't the check's progress (`logAside`).
    private func tell(_ line: String) {
        logAside(line)
        print(PrivateText.redacted(line))
        fflush(nil)
    }
}

let inputBlock = InputBlock()
