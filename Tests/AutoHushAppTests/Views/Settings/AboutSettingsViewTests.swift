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

    @Test("it shrinks by any amount but grows only by 3 pt or more while the room is tight, so two sizes never take turns")
    func growsOnlyBy3() {
        #expect(fitted(page: CGSize(width: 640, height: 519)) == 95) // 115 / (1 + 20/96)
        #expect(fitted(page: CGSize(width: 640, height: 522)) == 96) // 97 by the room
        #expect(fitted(page: CGSize(width: 640, height: 525)) == 100)
        // With room to spare, up to 128 by any amount (126 stayed, 2026-10-31).
        #expect(AboutSettingsView.fittedIconSize(current: 126, page: CGSize(width: 640, height: 900), content: 550,
                                                 name: CGSize(width: 104, height: 27)) == AboutSettingsView.largestIconSize)
    }

    @Test("the page's height at another icon size: the icon's and the name's heights follow it")
    func contentAtAnotherSize() {
        // 520 beside 96 with a 20 pt name: at 64, 32 less for the icon and a third of the name's 20.
        let atLeast = AboutSettingsView.contentHeight(atIcon: 64, current: 96, content: 520, name: CGSize(width: 80, height: 20))
        #expect(abs(atLeast - (520 - 32 - 20.0 / 3)) < 0.001)
    }

    @Test("the icon goes back above the name only with 2 pt to spare, so the two headers never take turns")
    func stackedFitsAgain() {
        // The compact page 470 tall, the stacked one 50 taller.
        #expect(AboutSettingsView.stackedFits(page: CGSize(width: 480, height: 522), compactContent: 470, stackedExtra: 50))
        #expect(!AboutSettingsView.stackedFits(page: CGSize(width: 480, height: 521), compactContent: 470, stackedExtra: 50))
        #expect(!AboutSettingsView.stackedFits(page: .zero, compactContent: 0, stackedExtra: 0))
    }

    @Test("the name stays on one line; nothing measured yet, the page included, it stays as it is")
    func nameAndUnmeasured() {
        #expect(fitted(page: CGSize(width: 200, height: 900), name: CGSize(width: 200, height: 20)) == 76) // 160 × 96 / 200
        #expect(fitted(page: CGSize(width: 640, height: 600), content: 0) == 96)
        #expect(fitted(page: CGSize(width: 640, height: 600), name: .zero) == 96)
        #expect(fitted(page: .zero) == 96) // the page not laid out yet
    }
}
