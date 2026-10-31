import CoreGraphics
import Foundation
import Testing
@testable import AutoHushApp

@Suite("AboutSettingsView")
struct AboutSettingsViewTests {
    /// A page whose content, at a 96 pt icon, is 520 pt tall with a name 20 pt
    /// tall and 80 wide.
    private func fitted(page: CGSize, content: CGFloat = 520, name: CGSize = CGSize(width: 80, height: 20)) -> CGFloat {
        AboutSettingsView.fittedIconSize(current: 96, page: page, content: content, name: name)
    }

    @Test("the icon and the name take the room the page leaves, together, up to 128 pt")
    func growsUpTo128() {
        #expect(fitted(page: CGSize(width: 640, height: 540)) == 112) // (540 - 404) / (1 + 20/96)
        #expect(fitted(page: CGSize(width: 640, height: 900)) == AboutSettingsView.largestIconSize)
    }

    @Test("they shrink so the page fits, down to 64 pt, where a page too short scrolls")
    func shrinksTo64() {
        #expect(fitted(page: CGSize(width: 640, height: 480)) == AboutSettingsView.leastIconSize) // 62 by the room
        #expect(fitted(page: CGSize(width: 640, height: 300)) == AboutSettingsView.leastIconSize)
    }

    @Test("the name stays on one line; nothing measured yet, it stays as it is")
    func nameAndUnmeasured() {
        #expect(fitted(page: CGSize(width: 200, height: 900), name: CGSize(width: 200, height: 20)) == 76) // 160 × 96 / 200
        #expect(fitted(page: CGSize(width: 640, height: 600), content: 0) == 96)
        #expect(fitted(page: CGSize(width: 640, height: 600), name: .zero) == 96)
    }
}
