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
}
