import CoreGraphics
import Testing
@testable import CheckedPlayers

/// The window rules Player Check's check and Add an App's wait share.
@Suite("AppWindows")
struct AppWindowsTests {
    @Test("a window is covered only when the windows above it hold every point of a 9×9 grid over it, edges included, within half a point")
    func covered() {
        let box = CGRect(x: 100, y: 100, width: 400, height: 300)
        let left = CGRect(x: 100, y: 100, width: 200, height: 300), right = CGRect(x: 300, y: 100, width: 200, height: 300)
        #expect(AppWindows.isCovered(box: box, above: [box]))
        #expect(AppWindows.isCovered(box: box, above: [box.insetBy(dx: 0.4, dy: 0.4)])) // within half a point
        #expect(!AppWindows.isCovered(box: box, above: [box.insetBy(dx: 1, dy: 1)])) // its edges show
        #expect(AppWindows.isCovered(box: box, above: [left, right]))
        #expect(!AppWindows.isCovered(box: box, above: [left]))
        #expect(!AppWindows.isCovered(box: box, above: []))
    }

    @Test("an ordinary window: a document window's layer, and a standard window whatever its height, or any other at least 200 points tall")
    func ordinaryWindows() {
        #expect(AppWindows.isOrdinary(layer: 0, height: 130, isStandard: true)) // a movie player's for sound alone
        #expect(AppWindows.isOrdinary(layer: 0, height: 200, isStandard: false))
        #expect(!AppWindows.isOrdinary(layer: 0, height: 199, isStandard: false)) // a strip, a helper
        #expect(!AppWindows.isOrdinary(layer: 3, height: 600, isStandard: true))
        #expect(!AppWindows.isOrdinary(layer: nil, height: 600, isStandard: true))
    }

    @Test("a window kept closed is off screen and on no desktop; a hidden, minimized or other desktop's keeps one, and unread desktops tell nothing")
    func closedWindows() {
        #expect(AppWindows.isClosed(onScreen: false, desktops: [])) // a menu bar player's, playing on
        #expect(!AppWindows.isClosed(onScreen: false, desktops: [1])) // hidden, minimized, or on another desktop
        #expect(!AppWindows.isClosed(onScreen: false, desktops: nil))
        #expect(!AppWindows.isClosed(onScreen: true, desktops: []))
    }

    @Test("the window found before spares the full look only while it's still listed as the app's and on screen")
    func reachableShortcut() {
        func window(_ number: Int, owner: pid_t = 42, onScreen: Bool) -> AppWindows.Info {
            [kCGWindowNumber as String: number, kCGWindowOwnerPID as String: Int(owner),
             kCGWindowLayer as String: 0, kCGWindowIsOnscreen as String: onScreen]
        }
        let other = window(8, onScreen: true)
        #expect(AppWindows.isReachableShortcut(listed: [other, window(7, onScreen: true)], known: 7, pid: 42))
        #expect(!AppWindows.isReachableShortcut(listed: [other, window(7, onScreen: false)], known: 7, pid: 42)) // off screen: the full look runs
        #expect(!AppWindows.isReachableShortcut(listed: [other], known: 7, pid: 42)) // closed, gone from the list
        #expect(!AppWindows.isReachableShortcut(listed: [window(7, owner: 99, onScreen: true)], known: 7, pid: 42)) // another app's
        #expect(!AppWindows.isReachableShortcut(listed: [other], known: nil, pid: 42)) // none known yet
        #expect(!AppWindows.isReachableShortcut(listed: [], known: 7, pid: 42))
    }
}
