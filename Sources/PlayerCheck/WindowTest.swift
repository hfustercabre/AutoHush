import AppKit

// MARK: - A test's trip through the window states

/// A test's trip through the window states: where the app's window was
/// (put back at the end, or at a stop), the app to come back to before each
/// state's trials (the one running this tool, the Player Check app, else the
/// one in front at the start), and which states can be tested here.
@MainActor final class WindowTest {
    let app: NSRunningApplication
    var pid: pid_t { app.processIdentifier }
    let home: NSRunningApplication?
    let original: WindowState
    private let originalFrame: CGRect
    private let homeDesktop: Int?
    /// The desktop its window goes back to: where it was, or, for one
    /// minimized or hidden, where it shows again (read the first time it's
    /// shown: a minimized window has no desktop of its own until then).
    private var ownDesktop: Int?
    private var firstTrip = true
    /// Other apps' windows over it at the start (when it was covered), front
    /// first: raised again at the end.
    private let coverers: [(pid: pid_t, window: Int)]
    /// The home app's window, when it was moved aside for the app's to show, and where it was.
    private var homeWindow: (element: AXUIElement, frame: CGRect)?
    /// The home app's window in front when the test began, brought back each
    /// time: the one the check was started from (AutoHush's Add an App), not
    /// its biggest (Settings, which then covered it).
    private let homeFront: Int?
    private let cover = CoverWindow()
    /// Why each state that can't be tested isn't.
    var untested: [WindowState: String] = [:]
    /// Shows the app's page to Accessibility (its switch on) while its window
    /// is dragged, and hides it after: an Electron app's top bar has buttons
    /// Accessibility sees only then (an account's avatar).
    var revealPage: ((Bool) -> Void)?
    var states: [WindowState] { WindowState.allCases.filter { untested[$0] == nil } }

    init?(app: NSRunningApplication) {
        self.app = app
        let pid = app.processIdentifier
        let parent = NSRunningApplication(processIdentifier: getppid())
        let front = frontAtStart ?? WindowStates.frontPID().flatMap { NSRunningApplication(processIdentifier: $0) }
        let home = parent?.activationPolicy == .regular ? parent : front?.processIdentifier == pid ? nil : front
        self.home = home
        homeFront = home.flatMap { WindowStates.frontWindow(of: $0.processIdentifier) }
        // Read from the home app's desktop: whoever started the app playing
        // may have gone to its desktop for it, and from there its window read
        // as visible, that desktop was taken for home, and the first state
        // was never reached.
        if let home { Self.show(home, window: homeFront) }
        guard let state = WindowStates.state(of: app), let (info, element) = WindowStates.main(of: pid) else { return nil }
        original = state
        originalFrame = element?.frame ?? WindowStates.frame(of: info)
        ownDesktop = state == .fullScreen ? nil : Desktops.of(window: WindowStates.number(of: info))
        coverers = state != .covered ? [] : WindowStates.windowsAbove(info)
            .filter { ![pid, home?.processIdentifier ?? 0, getpid()].contains($0.pid) }
            .map { ($0.pid, $0.window) }
        let desktops = Desktops.all()
        homeDesktop = desktops?.current
        // Full screen apps' desktops don't count: they go with their window.
        if desktops.map({ $0.spaces.filter { !$0.isFullScreen }.count < 2 }) ?? true {
            let why = desktops == nil ? "macOS's desktops can't be read" : "no other desktop: add one in Mission Control to test it"
            untested[.otherDesktop] = why
            untested[.otherDesktopCovered] = why
        }
    }

    private var element: AXUIElement? { WindowStates.main(of: pid)?.element }

    /// Back to the app the test came from (`show`).
    private func comeHome() {
        guard let home else { return log("  back: no app to come back to; in front: \(WindowStates.frontName)") }
        Self.show(home, window: homeFront)
        log("  back to \(home.localizedName ?? "the app it came from"): in front: \(WindowStates.frontName)")
    }

    /// The app the test came from in front, until its window is on screen.
    /// Brought forward, macOS may leave another desktop shown: from a full
    /// screen app's, or anywhere for Player Check (`open` brought it forward
    /// and stayed on the checked app's desktop, and SkyLight's way can't run on macOS 27:
    /// GetProcessForPID is gone), so its desktop is then shown with
    /// Control-arrow, as a person would, and it's brought forward there.
    private static func show(_ home: NSRunningApplication, window front: Int?) {
        let window = front.flatMap { number in WindowStates.infos(.optionAll).contains { WindowStates.number(of: $0) == number } ? number : nil }
            ?? WindowStates.main(of: home.processIdentifier).map { WindowStates.number(of: $0.info) }
        func shown() -> Bool {
            guard let window else { return true }
            return WindowStates.infos(.optionOnScreenOnly).contains { WindowStates.number(of: $0) == window }
        }
        WindowStates.activate(home, showing: window)
        Thread.sleep(forTimeInterval: 0.8) // desktops stop sliding
        guard !shown(), let window, let there = Desktops.of(window: window), there != Desktops.all()?.current,
              WindowStates.showDesktop(there) else { return }
        WindowStates.activate(home, showing: window)
        Thread.sleep(forTimeInterval: 0.3)
    }

    /// Shown, on this desktop, not minimized or full screen: the start of
    /// every other state.
    private func normalize() -> String? {
        cover.remove()
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1)
        if appElement.value(kAXHiddenAttribute) as? Bool == true {
            WindowStates.set(appElement, kAXHiddenAttribute, false)
            guard WindowStates.wait(3, until: { appElement.value(kAXHiddenAttribute) as? Bool != true }) else { return "it couldn't be shown again" }
        }
        // Out of sight and out of Accessibility's reach (a scriptable player's
        // window on another desktop: no element number answered): its desktop shown
        // first, where its window can be reached; then it's dragged back here
        // as any other. Bringing that app forward didn't show that desktop (some of
        // its hidden windows are on this one), so the desktop is shown with
        // Control-arrow, as a person would.
        if let (info, element) = WindowStates.main(of: pid), element == nil, info[kCGWindowIsOnscreen as String] as? Bool != true,
           let there = Desktops.of(window: WindowStates.number(of: info)), there != Desktops.all()?.current {
            guard WindowStates.showDesktop(there), WindowStates.wait(3, until: { self.element != nil }) else {
                comeHome()
                return "its window can't be reached, even with its desktop shown"
            }
        }
        guard let element else { return "its window can't be reached" }
        if element.value(kAXMinimizedAttribute) as? Bool == true {
            WindowStates.set(element, kAXMinimizedAttribute, false)
            guard WindowStates.wait(4, until: { element.value(kAXMinimizedAttribute) as? Bool != true }) else { return "it couldn't be unminimized" }
            Thread.sleep(forTimeInterval: 0.6)
        }
        if element.value("AXFullScreen") as? Bool == true {
            WindowStates.set(element, "AXFullScreen", false)
            guard WindowStates.wait(6, until: { element.value("AXFullScreen") as? Bool != true }) else { return "it couldn't leave full screen" }
            Thread.sleep(forTimeInterval: 1.2)
        }
        let there = WindowStates.main(of: pid).flatMap { Desktops.of(window: WindowStates.number(of: $0.info)) }
        if firstTrip, original == .minimized || original == .hidden { ownDesktop = there ?? homeDesktop }
        firstTrip = false
        if let homeDesktop, let there, there != homeDesktop {
            guard let from = Desktops.index(of: there), let to = Desktops.index(of: homeDesktop) else {
                return "its window is on another display's desktop"
            }
            guard WindowStates.move(app, desktops: to - from, reveal: revealPage) else { return "its window couldn't be dragged back to this desktop" }
        }
        return nil
    }

    /// Visible: when covered, brought forward, with the home app in front
    /// again; when the home app's window still covers it, that one is moved
    /// aside, put back at the end.
    private func showVisible() -> String? {
        guard let info = WindowStates.main(of: pid)?.info else { return "its window is gone" }
        guard WindowStates.isCovered(info) else { return nil }
        WindowStates.activate(app, showing: WindowStates.number(of: info))
        comeHome()
        guard let again = WindowStates.main(of: pid)?.info, WindowStates.isCovered(again) else { return nil }
        guard let home else { return "it's covered" }
        let homeApp = AXUIElementCreateApplication(home.processIdentifier)
        AXUIElementSetMessagingTimeout(homeApp, 1)
        guard let window = homeApp.element(kAXFocusedWindowAttribute) ?? homeApp.element(kAXMainWindowAttribute),
              let frame = window.frame else { return "it's covered" }
        if homeWindow == nil { homeWindow = (window, frame) }
        // Aside towards the side with room, leaving 160 pt of the app's window
        // in view; narrower when the screen is too small.
        let target = WindowStates.frame(of: again)
        let screen = NSScreen.screens.first?.visibleFrame ?? .zero
        var moved = frame
        if target.midX >= frame.midX {
            moved.origin.x = target.maxX - 160 - frame.width
            if moved.minX < screen.minX {
                moved.origin.x = screen.minX
                moved.size.width = max(400, target.maxX - 160 - screen.minX)
            }
        } else {
            moved.origin.x = target.minX + 160
            if moved.maxX > screen.maxX { moved.size.width = max(400, screen.maxX - moved.minX) }
        }
        WindowStates.setFrame(window, moved)
        Thread.sleep(forTimeInterval: 0.5)
        guard let after = WindowStates.main(of: pid)?.info, !WindowStates.isCovered(after) else {
            return "it's covered by \(home.localizedName ?? "the app in front")'s window, which couldn't be moved aside"
        }
        return nil
    }

    /// Puts the app's window in `state`, with the home app in front after;
    /// nil once it reads so, else why it couldn't be.
    func putIn(_ state: WindowState) -> String? {
        if let why = untested[state] { return why }
        let why: String?
        switch state {
        case .visible:
            why = normalize() ?? showVisible()
        case .covered:
            why = normalize() ?? showVisible() ?? coverIt()
        case .otherDesktop:
            why = normalize() ?? toOtherDesktop()
        case .otherDesktopCovered:
            let there = WindowStates.state(of: app) == .otherDesktop
            why = (there ? nil : normalize() ?? toOtherDesktop()) ?? coverOnItsDesktop()
        case .fullScreen:
            why = normalize() ?? setWindow("AXFullScreen", reads: .fullScreen, within: 6)
        case .minimized:
            why = normalize() ?? setWindow(kAXMinimizedAttribute, reads: .minimized, within: 4)
        case .hidden:
            why = normalize() ?? hide()
        }
        if let why { return why }
        comeHome()
        let now = WindowStates.state(of: app)
        // Covered on its desktop by this tool's window, there with it (the
        // window list can't tell covered there: `state(of:)`).
        if state == .otherDesktopCovered, now == .otherDesktop, let number = cover.number,
           let info = WindowStates.main(of: pid)?.info, Desktops.of(window: number) == Desktops.of(window: WindowStates.number(of: info)) {
            return nil
        }
        return now == state ? nil : "it reads as " + (now?.title ?? "having no window")
    }

    private func coverIt() -> String? {
        guard let info = WindowStates.main(of: pid)?.info else { return "its window is gone" }
        cover.show(over: WindowStates.frame(of: info), naming: appName)
        return nil
    }

    /// To the nearest other desktop (the next first), chosen now: a full
    /// screen app's desktop between the two is passed by.
    private func toOtherDesktop() -> String? {
        guard let desktops = Desktops.all(), let here = desktops.spaces.firstIndex(where: { $0.id == desktops.current }) else {
            return "macOS's desktops can't be read"
        }
        let others = desktops.spaces.indices.filter { $0 != here && !desktops.spaces[$0].isFullScreen }
        guard let nearest = others.min(by: { abs($0 - here) < abs($1 - here) || (abs($0 - here) == abs($1 - here) && $0 > $1) }) else {
            return "no other desktop: add one in Mission Control to test it"
        }
        return WindowStates.move(app, desktops: nearest - here, reveal: revealPage) ? nil : "its window couldn't be dragged to another desktop"
    }

    private func coverOnItsDesktop() -> String? {
        guard let info = WindowStates.main(of: pid)?.info else { return "its window is gone" }
        let number = WindowStates.number(of: info)
        // Brought forward there; else that desktop shown with Control-arrow
        // (an app's coming forward didn't show it: `normalize`).
        if !WindowStates.activate(app, showing: number) {
            guard let there = Desktops.of(window: number), WindowStates.showDesktop(there) else { return "its desktop couldn't be shown" }
        }
        Thread.sleep(forTimeInterval: 0.6)
        return coverIt()
    }

    private func setWindow(_ attribute: String, reads state: WindowState, within seconds: Double) -> String? {
        guard let element else { return "its window can't be reached" }
        WindowStates.set(element, attribute, true)
        guard WindowStates.wait(seconds, until: { WindowStates.state(of: app) == state }) else { return "it didn't go \(state.title)" }
        if state == .fullScreen {
            // Its own desktop slides in for about a second: coming home meanwhile
            // leaves that desktop shown (and the menu bar hidden with it).
            let window = WindowStates.main(of: pid).map { WindowStates.number(of: $0.info) }
            _ = WindowStates.wait(3, until: { window.flatMap(Desktops.of(window:)) == Desktops.all()?.current })
            Thread.sleep(forTimeInterval: 1)
        } else {
            Thread.sleep(forTimeInterval: 0.6)
        }
        return nil
    }

    private func hide() -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1)
        WindowStates.set(appElement, kAXHiddenAttribute, true)
        if !WindowStates.wait(2, until: { appElement.value(kAXHiddenAttribute) as? Bool == true }) { app.hide() }
        return WindowStates.wait(2, until: { appElement.value(kAXHiddenAttribute) as? Bool == true }) ? nil : "it couldn't be hidden"
    }

    /// The other apps' windows that covered it, raised again, the back one
    /// first, so the front one ends in front.
    private func coverAgain() {
        for coverer in coverers.reversed() {
            guard let app = NSRunningApplication(processIdentifier: coverer.pid), !app.isTerminated else { continue }
            WindowStates.activate(app, showing: coverer.window)
        }
    }

    /// Back as it was at the start: its state, place and desktop, the other
    /// apps' windows over it again, the home app's window and the home app in
    /// front. What it couldn't put back, or nil.
    @discardableResult
    func restore() -> String? {
        var problem = normalize()
        if problem == nil, original != .fullScreen, let element { WindowStates.setFrame(element, originalFrame) }
        if problem == nil, original != .fullScreen, let ownDesktop, let homeDesktop, ownDesktop != homeDesktop {
            if let from = Desktops.index(of: homeDesktop), let to = Desktops.index(of: ownDesktop),
               WindowStates.move(app, desktops: to - from, reveal: revealPage) {
            } else {
                problem = "its window couldn't be dragged back to its desktop"
            }
        }
        if problem == nil {
            switch original {
            case .fullScreen: problem = setWindow("AXFullScreen", reads: .fullScreen, within: 6)
            case .minimized: problem = setWindow(kAXMinimizedAttribute, reads: .minimized, within: 4)
            case .hidden: problem = hide()
            case .covered: coverAgain()
            case .visible, .otherDesktop, .otherDesktopCovered: break
            }
        }
        if let homeWindow { WindowStates.setFrame(homeWindow.element, homeWindow.frame) }
        if original != .hidden || home != nil { comeHome() }
        stopState.windowBack()
        return problem
    }
}

/// The window state the test has the app in now: nil outside one (or before
/// the first). Out of view, a Chromium page's words lag (`wordsCurrent`).
@MainActor var currentWindowState: WindowState?
/// The trip through the window states, for a test of an app with a window
/// (and the Accessibility permission to move it).
@MainActor var windowTest: WindowTest?
/// Why there are no window states, when there aren't.
@MainActor var windowStatesNote: String?
