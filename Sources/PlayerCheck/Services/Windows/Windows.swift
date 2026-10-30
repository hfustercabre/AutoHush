import AppKit
import AutoHushKit
import WebAppPlayers

// MARK: - The app's windows, as AutoHush finds them

/// The windows last found on other desktops: the search takes about 70 ms
/// (up to 1 s), and pages are read every quarter second, so they're kept
/// for 10 s while each still answers as a window.
@MainActor var otherDesktopWindows: (pid: pid_t, windows: [AXUIElement], found: Date)?

/// The app's windows on this desktop, else on any other, as AutoHush finds
/// them (`AccessibilityWebPage.windows`, through `AccessibilityWindows`:
/// about 70 ms, 1 s at most), each read waiting 1 s; `onThisDesktop` false:
/// not on screen, so nothing there can be hit-tested.
@MainActor func appWindows(of pid: pid_t) -> (windows: [AXUIElement], onThisDesktop: Bool) {
    AccessibilityWebPage.windows(of: pid, timeout: 1) { pid in
        guard AccessibilityWindows.isAvailable else { return nil }
        if let kept = otherDesktopWindows, kept.pid == pid, Date().timeIntervalSince(kept.found) < 10,
           !kept.windows.isEmpty, kept.windows.allSatisfy({ $0.text(kAXRoleAttribute) == kAXWindowRole }) {
            return kept.windows
        }
        let found = AccessibilityWindows.windows(ofProcess: pid) ?? []
        otherDesktopWindows = (pid, found, Date())
        return found
    }
}

/// Whether what a window shows can be hit-tested: it's on this desktop, not
/// minimized, and its app isn't hidden.
func isOnScreen(_ window: AXUIElement, onThisDesktop: Bool, appHidden: Bool) -> Bool {
    onThisDesktop && !appHidden && window.value(kAXMinimizedAttribute) as? Bool != true
}
