import AppKit
import AutoHushKit

/// Reading an app's windows as Player Check does: its main window, whether
/// it's closed (a menu bar player keeps its own, playing on), and the state
/// it's in (`CheckResult.WindowState`). Player Check moves the window
/// through those states (`WindowStates`); Add an App waits, after Check
/// Again, for a window the check can reach (`hasWindowWithinReach`), so both
/// tell them by the same rule. Each look at the windows on other desktops
/// takes about 70 ms, up to 1 s: off the main actor in an app.
package enum AppWindows {
    package typealias Info = [String: Any]
    package static func infos(_ option: CGWindowListOption) -> [Info] {
        CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [Info] ?? []
    }
    package static func frame(of info: Info) -> CGRect {
        (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
    }
    package static func number(of info: Info) -> Int { info[kCGWindowNumber as String] as? Int ?? 0 }
    package static func owner(of info: Info) -> pid_t { info[kCGWindowOwnerPID as String] as? pid_t ?? 0 }

    /// The app's main window, and its Accessibility element when it can be
    /// reached, from one look at its windows (the search for windows on
    /// other desktops takes about 70 ms, up to 1 s): its biggest ordinary one
    /// that Accessibility knows, wherever it is (a full screen window may
    /// come with a bigger one it doesn't: an Apple player's), else its
    /// biggest not closed, else its biggest.
    package static func main(of pid: pid_t) -> (info: Info, element: AXUIElement?)? {
        let known = windowElements(of: pid)
        let standard = standardWindows(in: known)
        let candidates = infos(.optionAll).filter { owner(of: $0) == pid && isOrdinary($0, standard: standard) }
        guard !candidates.isEmpty else { return nil }
        func area(_ info: Info) -> CGFloat { frame(of: info).width * frame(of: info).height }
        func largest(_ infos: [Info]) -> Info? { infos.max { area($0) < area($1) } }
        let numbers = Set(known.map(\.number))
        guard let info = largest(candidates.filter { numbers.contains(number(of: $0)) })
                ?? largest(candidates.filter { !isClosed($0) })
                ?? largest(candidates) else { return nil }
        return (info, known.first { $0.number == number(of: info) }?.element)
    }

    /// A window the app keeps closed (`isClosed(onScreen:desktops:)`).
    package static func isClosed(_ info: Info) -> Bool {
        let onScreen = info[kCGWindowIsOnscreen as String] as? Bool == true
        return isClosed(onScreen: onScreen, desktops: onScreen ? nil : Desktops.all(ofWindow: number(of: info)))
    }

    /// A window kept closed: off screen and on no desktop, as a menu bar
    /// player keeps its own, playing on (2026-10-27). A minimized or hidden
    /// window keeps its desktop, and one on another desktop has that one;
    /// with its desktops unread, it isn't taken for closed.
    package static func isClosed(onScreen: Bool, desktops: [Int]?) -> Bool {
        !onScreen && desktops?.isEmpty == true
    }

    /// Its window in front among its ordinary ones on screen (the list goes
    /// front to back), when it has one.
    package static func frontWindow(of pid: pid_t) -> Int? {
        let standard = standardWindows(in: windowElements(of: pid))
        return infos(.optionOnScreenOnly).first { owner(of: $0) == pid && isOrdinary($0, standard: standard) }.map(number(of:))
    }

    /// An ordinary window: a document window's layer, and either a standard
    /// window to Accessibility, whatever its height (a movie player's for
    /// sound alone can be about 130 points tall), or at least 200 points tall
    /// (not a strip or a helper).
    package static func isOrdinary(_ info: Info, standard: Set<Int>) -> Bool {
        isOrdinary(layer: info[kCGWindowLayer as String] as? Int, height: frame(of: info).height, isStandard: standard.contains(number(of: info)))
    }

    /// `isOrdinary`'s rule, on what it reads of the window.
    package static func isOrdinary(layer: Int?, height: CGFloat, isStandard: Bool) -> Bool {
        layer == 0 && (isStandard || height >= 200)
    }

    /// The numbers of the windows Accessibility calls standard ones, and of
    /// the minimized ones (macOS 14.4 calls a minimized window a dialog).
    package static func standardWindows(in known: [(number: Int, element: AXUIElement)]) -> Set<Int> {
        Set(known.filter {
            $0.element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole || $0.element.value(kAXMinimizedAttribute) as? Bool == true
        }.map(\.number))
    }

    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindow = PrivateSymbol.function("_AXUIElementGetWindow", as: GetWindow.self)

    /// The app's windows Accessibility knows, with their numbers: this
    /// desktop's (minimized ones too) and every other's (`AccessibilityWindows`),
    /// each read waiting 1 s.
    package static func windowElements(of pid: pid_t) -> [(number: Int, element: AXUIElement)] {
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
    package static func element(of pid: pid_t, number: Int) -> AXUIElement? {
        windowElements(of: pid).first { $0.number == number }?.element
    }

    /// The windows on screen above `info` that overlap it, front first, with their apps.
    package static func windowsAbove(_ info: Info) -> [(pid: pid_t, window: Int, frame: CGRect)] {
        let list = infos(.optionOnScreenOnly)
        guard let index = list.firstIndex(where: { number(of: $0) == number(of: info) }) else { return [] }
        let box = frame(of: info)
        return list[..<index].filter { other in
            other[kCGWindowLayer as String] as? Int == 0 && (other[kCGWindowAlpha as String] as? Double ?? 1) > 0
                && frame(of: other).insetBy(dx: -0.5, dy: -0.5).intersects(box)
        }.map { (owner(of: $0), number(of: $0), frame(of: $0)) }
    }

    /// Whether the windows on screen above it cover every point of a grid over it.
    package static func isCovered(_ info: Info) -> Bool {
        guard infos(.optionOnScreenOnly).contains(where: { number(of: $0) == number(of: info) }) else { return false }
        return isCovered(box: frame(of: info), above: windowsAbove(info).map(\.frame))
    }

    /// `isCovered`'s rule: whether `above` holds every point of a 9×9 grid
    /// over `box`, edges included, a window within half a point counting.
    package static func isCovered(box: CGRect, above: [CGRect]) -> Bool {
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
    /// A closed window an app keeps counts as none, hidden or not (its
    /// windows closed: a menu bar player's was read as on another desktop,
    /// and every state as out of reach, 2026-10-27).
    package static func state(of app: NSRunningApplication) -> CheckResult.WindowState? {
        state(of: app, main: main(of: app.processIdentifier))
    }

    /// `state(of:)`, its main window found already (`main(of:)`).
    private static func state(of app: NSRunningApplication, main: (info: Info, element: AXUIElement?)?) -> CheckResult.WindowState? {
        let appElement = AXUIElement.application(app.processIdentifier, timeout: 1)
        let hidden = appElement.value(kAXHiddenAttribute) as? Bool == true
        guard let (info, element) = main else { return hidden ? .hidden : nil }
        if isClosed(info) { return nil }
        if hidden { return .hidden }
        if element?.value(kAXMinimizedAttribute) as? Bool == true { return .minimized }
        if element?.value("AXFullScreen") as? Bool == true { return .fullScreen }
        if info[kCGWindowIsOnscreen as String] as? Bool == true { return isCovered(info) ? .covered : .visible }
        // Off screen on this very desktop: closed, as an Electron app keeps a
        // closed window (a player's, playing on), or ordered out.
        if let desktop = Desktops.of(window: number(of: info)), desktop == Desktops.all()?.current { return nil }
        return .otherDesktop
    }

    /// Whether the app has a window the check can reach and move (on
    /// screen, covered, minimized, hidden, full screen, on another
    /// desktop): Player Check's `WindowTest(app:)` rule. Without one, the
    /// check runs with its windows closed (each way tried once).
    package static func hasWindowWithinReach(_ app: NSRunningApplication) -> Bool {
        // One look at its windows, for its state and its main window.
        let found = main(of: app.processIdentifier)
        guard let state = state(of: app, main: found) else { return false }
        // Hidden is the app's: it may have no main window then.
        return state != .hidden || found != nil
    }
}
