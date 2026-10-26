import CoreGraphics
import Testing
@testable import AutoHushApp

/// Whether the menu bar icon can be seen: on the screen and not behind the
/// notch, whatever the window says of itself.
@Suite("MenuBarIconVisibility")
struct MenuBarIconVisibilityTests {
    /// A 1512-point-wide screen whose notch spans 662 to 850 (MacBook Pro 14").
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let left: CGFloat = 662, right: CGFloat = 662

    private func icon(at x: CGFloat) -> CGRect { CGRect(x: x, y: 949, width: 38, height: 33) }

    @Test("beside the system's icons, or left of the notch, it shows; behind the notch it's hidden")
    func notch() {
        #expect(!MenuBarIconVisibility.isHidden(icon: icon(at: 1200), isVisible: true, screen: screen, leftOfNotch: left, rightOfNotch: right))
        #expect(!MenuBarIconVisibility.isHidden(icon: icon(at: 600), isVisible: true, screen: screen, leftOfNotch: left, rightOfNotch: right))
        #expect(MenuBarIconVisibility.isHidden(icon: icon(at: 740), isVisible: true, screen: screen, leftOfNotch: left, rightOfNotch: right))
    }

    @Test("without a notch it shows anywhere on the screen; off the screen, or its window not shown, it's hidden")
    func noNotch() {
        #expect(!MenuBarIconVisibility.isHidden(icon: icon(at: 740), isVisible: true, screen: screen, leftOfNotch: nil, rightOfNotch: nil))
        #expect(MenuBarIconVisibility.isHidden(icon: icon(at: -100), isVisible: true, screen: screen, leftOfNotch: nil, rightOfNotch: nil))
        #expect(MenuBarIconVisibility.isHidden(icon: icon(at: 1200), isVisible: false, screen: screen, leftOfNotch: nil, rightOfNotch: nil))
    }

    @Test("a screen to the right of the main one: the notch is measured from its own left edge")
    func secondScreen() {
        let second = screen.offsetBy(dx: 1512, dy: 0)
        #expect(MenuBarIconVisibility.isHidden(icon: icon(at: 1512 + 740), isVisible: true, screen: second, leftOfNotch: left, rightOfNotch: right))
        #expect(!MenuBarIconVisibility.isHidden(icon: icon(at: 1512 + 1200), isVisible: true, screen: second, leftOfNotch: left, rightOfNotch: right))
    }
}
