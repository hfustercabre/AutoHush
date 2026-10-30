import ApplicationServices
import AutoHushKit

// AccessibilityWebPage: an app's windows, and the pages and items in them.
extension AccessibilityWebPage {
    /// The page is this deep in a window at most (measured: 3 to 5), and
    /// found among this many of the window's elements, read breadth first,
    /// not walking into lists: a native app's window isn't read whole.
    private static let webAreaDepth = 16
    private static let webAreaReadLimit = 2000
    /// A Flutter window's pressable items are this deep at most, among this
    /// many of its elements.
    private static let itemDepth = 40
    private static let itemReadLimit = 3000
    /// Roles never walked into looking for a page: a native app's long lists
    /// (Music's songs) hold none.
    private static let listRoles: Set<String> = [kAXTableRole, kAXOutlineRole, kAXBrowserRole, kAXListRole, "AXGrid", kAXTextAreaRole]

    // MARK: - Windows and pages

    /// The app's windows on the current Space (minimized ones too), else on
    /// any Space.
    func windows(of pid: pid_t) -> [AXUIElement] { Self.windows(of: pid).windows }

    /// The windows of the app running as `pid` on the current Space
    /// (minimized ones too), else on any other (`elsewhere`: through
    /// `AccessibilityWindows`, about 70 ms), each read waiting `timeout`;
    /// `onThisDesktop` false for those. Player Check finds an app's windows
    /// with this (keeping those found elsewhere a while, and waiting longer).
    package static func windows(of pid: pid_t, timeout: Float = AccessibilityWebPage.timeout,
                                elsewhere: (pid_t) -> [AXUIElement]? = AccessibilityWindows.windows(ofProcess:))
        -> (windows: [AXUIElement], onThisDesktop: Bool) {
        let shown = AXUIElement.application(pid, timeout: timeout).elements(kAXWindowsAttribute, timeout: timeout)
        guard shown.isEmpty else { return (shown, true) }
        return ((elsewhere(pid) ?? []).map { $0.waiting(timeout) }, false)
    }

    /// The web pages (AXWebArea) in a window, nearest first, reading at most
    /// `webAreaReadLimit` of its elements and none inside a list.
    package static func webAreas(in window: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []
        walk(from: window, limit: webAreaReadLimit, maxDepth: webAreaDepth) { element, _ in
            let role = element.string(kAXRoleAttribute) ?? ""
            if role == "AXWebArea" {
                found.append(element)
                return false
            }
            return !listRoles.contains(role)
        }
        return found
    }

    /// A Flutter window's items that can be pressed (its buttons, and the
    /// texts and images it marks pressable); not the window's own close,
    /// minimize and full-screen buttons.
    static func pressableItems(in window: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []
        walk(from: window, limit: itemReadLimit, maxDepth: itemDepth) { element, depth in
            if depth == 1, element.string(kAXRoleAttribute) == kAXButtonRole { return false }
            if depth > 0, element.actionNames.contains(kAXPressAction) { found.append(element) }
            return true
        }
        return found
    }

    /// Walks an element's tree breadth first, reading at most `limit`
    /// elements and going at most `maxDepth` levels down, each read waiting
    /// `timeout`; `visit` says whether to go into each one's children.
    static func walk(from root: AXUIElement, limit: Int, maxDepth: Int, _ visit: (AXUIElement, Int) -> Bool) {
        var queue: [(AXUIElement, Int)] = [(root, 0)], next = 0
        while next < queue.count, next < limit {
            let (element, depth) = queue[next]
            next += 1
            if visit(element, depth), depth < maxDepth { queue += element.children(timeout: timeout).map { ($0, depth + 1) } }
        }
    }
}
