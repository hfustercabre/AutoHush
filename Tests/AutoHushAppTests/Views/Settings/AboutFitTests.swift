import CoreGraphics
import Foundation
import Testing
@testable import AutoHushApp

@Suite("AboutFit")
struct AboutFitTests {
    /// A page whose content, at a 96 pt icon, is 520 pt tall with a name 20 pt
    /// tall and 80 wide.
    private func fitted(page: CGSize, content: CGFloat = 520, name: CGSize = CGSize(width: 80, height: 20)) -> CGFloat {
        AboutFit.fittedIconSize(current: 96, page: page, content: content, name: name)
    }

    /// That page measured at 96 pt as About measures it: the page, the
    /// content, then the name.
    private func measured(page: CGSize, from start: AboutFit = AboutFit()) -> AboutFit {
        var fit = start
        fit.pageChanged(to: page)
        fit.contentMeasured(height: 520)
        fit.nameMeasured(CGSize(width: 80, height: 20))
        return fit
    }

    @Test("the icon and the name take the room the page leaves, together, up to 128 pt")
    func growsUpTo128() {
        #expect(fitted(page: CGSize(width: 640, height: 540)) == 112) // (540 - 404) / (1 + 20/96)
        #expect(fitted(page: CGSize(width: 640, height: 900)) == AboutFit.largestIconSize)
    }

    @Test("they shrink so the page fits, down to 64 pt, where a page too short scrolls")
    func shrinksTo64() {
        #expect(fitted(page: CGSize(width: 640, height: 480)) == AboutFit.leastIconSize) // 62 by the room
        #expect(fitted(page: CGSize(width: 640, height: 300)) == AboutFit.leastIconSize)
    }

    @Test("it shrinks by any amount but grows only by 3 pt or more while the room is tight, so two sizes never take turns")
    func growsOnlyBy3() {
        #expect(fitted(page: CGSize(width: 640, height: 519)) == 95) // 115 / (1 + 20/96)
        #expect(fitted(page: CGSize(width: 640, height: 522)) == 96) // 97 by the room
        #expect(fitted(page: CGSize(width: 640, height: 525)) == 100)
        // With room to spare, up to 128 by any amount (126 stayed, 2026-10-31).
        #expect(AboutFit.fittedIconSize(current: 126, page: CGSize(width: 640, height: 900), content: 550,
                                        name: CGSize(width: 104, height: 27)) == AboutFit.largestIconSize)
    }

    @Test("the page's height at another icon size: the icon's and the name's heights follow it")
    func contentAtAnotherSize() {
        // 520 beside 96 with a 20 pt name: at 64, 32 less for the icon and a third of the name's 20.
        let atLeast = AboutFit.contentHeight(atIcon: 64, current: 96, content: 520, name: CGSize(width: 80, height: 20))
        #expect(abs(atLeast - (520 - 32 - 20.0 / 3)) < 0.001)
    }

    @Test("the name's size beside another icon follows it, so a fit needn't wait for the name measured again")
    func nameAtAnotherSize() {
        let name = AboutFit.nameSize(CGSize(width: 80, height: 20), measuredBeside: 96, at: 72)
        #expect(name == CGSize(width: 60, height: 15))
        #expect(AboutFit.nameSize(CGSize(width: 80, height: 20), measuredBeside: 0, at: 72) == CGSize(width: 80, height: 20))
    }

    @Test("the icon goes back above the name only with 2 pt to spare, so the two headers never take turns")
    func stackedFitsAgain() {
        // The compact page 470 tall, the stacked one 50 taller.
        #expect(AboutFit.stackedFits(page: CGSize(width: 480, height: 522), compactContent: 470, stackedExtra: 50))
        #expect(!AboutFit.stackedFits(page: CGSize(width: 480, height: 521), compactContent: 470, stackedExtra: 50))
        #expect(!AboutFit.stackedFits(page: .zero, compactContent: 0, stackedExtra: 0))
    }

    @Test("the name stays on one line; nothing measured yet, the page included, it stays as it is")
    func nameAndUnmeasured() {
        #expect(fitted(page: CGSize(width: 200, height: 900), name: CGSize(width: 200, height: 20)) == 76) // 160 × 96 / 200
        #expect(fitted(page: CGSize(width: 640, height: 600), content: 0) == 96)
        #expect(fitted(page: CGSize(width: 640, height: 600), name: .zero) == 96)
        #expect(fitted(page: .zero) == 96) // the page not laid out yet
    }

    @Test("it fits once the page, the content and the name are measured, then holds as they're measured at the new size")
    func fitsInSequence() {
        var fit = AboutFit()
        #expect(fit.iconSize == AboutFit.openingIconSize)
        fit.pageChanged(to: CGSize(width: 640, height: 540))
        fit.contentMeasured(height: 520)
        #expect(fit.iconSize == 96) // the name not measured yet
        fit.nameMeasured(CGSize(width: 80, height: 20))
        #expect(fit.iconSize == 112)
        // Measured again at 112: 16 pt more for the icon and a sixth of the name's 20.
        fit.contentMeasured(height: 520 + 16 + 20.0 * 16 / 96)
        fit.nameMeasured(CGSize(width: 80.0 * 112 / 96, height: 20.0 * 112 / 96))
        #expect(fit.iconSize == 112)
        #expect(!fit.isCompact)
    }

    @Test("a fit doesn't wait for the name measured again beside the new icon (the 1.2.9 review)")
    func fitsWithTheNameUnchanged() {
        var fit = measured(page: CGSize(width: 640, height: 540))
        #expect(fit.iconSize == 112)
        fit.contentMeasured(height: 520 + 16 + 20.0 * 16 / 96) // the name's rounded size unchanged: no report
        fit.pageChanged(to: CGSize(width: 640, height: 500))
        #expect(fit.iconSize == 79) // 96 / (1 + 23.3/112)
    }

    @Test("a page too short even at 64 pt puts the icon beside the name, at 0.5 pt over, and back above it with 2 pt to spare")
    func compactAndBack() {
        // At 64 pt the stacked page is 520 - 32 - 20/3 = 481.3 tall.
        let atLeast = measured(page: CGSize(width: 640, height: 481))
        #expect(!atLeast.isCompact)
        #expect(atLeast.iconSize == AboutFit.leastIconSize)

        var fit = measured(page: CGSize(width: 640, height: 480))
        #expect(fit.isCompact)
        #expect(fit.iconSize == AboutFit.leastIconSize)
        fit.contentMeasured(height: 440) // the compact page, 41.3 shorter
        #expect(abs(fit.stackedExtra - (481 + 1.0 / 3 - 440)) < 0.001)
        fit.pageChanged(to: CGSize(width: 640, height: 483))
        #expect(fit.isCompact)
        fit.pageChanged(to: CGSize(width: 640, height: 484))
        #expect(!fit.isCompact)
        // Stacked again at 64 pt, it grows only once the content is measured beside it.
        fit.pageChanged(to: CGSize(width: 640, height: 900))
        #expect(fit.iconSize == AboutFit.leastIconSize)
        fit.contentMeasured(height: 481 + 1.0 / 3)
        #expect(fit.iconSize == AboutFit.largestIconSize)
    }

    @Test("an opening starts where the last left the icon and the header, nothing measured, so the icon doesn't jump (I1)")
    func resumesTheLastOpening() {
        let first = AboutFit(resuming: nil)
        #expect(first.iconSize == AboutFit.openingIconSize)
        #expect(!first.isCompact)

        let next = AboutFit(resuming: measured(page: CGSize(width: 640, height: 540)))
        #expect(next.iconSize == 112)
        #expect(!next.isCompact)
        #expect(next.pageSize == .zero && next.contentHeight == 0 && next.nameSize == .zero)
        #expect(next.measuredBeside.content == 0 && next.measuredBeside.name == 0)
        // The same page measured at 112: it stays.
        var fit = next
        fit.pageChanged(to: CGSize(width: 640, height: 540))
        fit.contentMeasured(height: 520 + 16 + 20.0 * 16 / 96)
        fit.nameMeasured(CGSize(width: 80.0 * 112 / 96, height: 20.0 * 112 / 96))
        #expect(fit.iconSize == 112)
    }

    @Test("a compact opening resumes compact only with its way back measured")
    func resumesCompact() {
        var compact = measured(page: CGSize(width: 640, height: 480))
        // Just switched, the compact page not measured yet: stacked at 64 pt.
        let unmeasured = AboutFit(resuming: compact)
        #expect(!unmeasured.isCompact)
        #expect(unmeasured.iconSize == AboutFit.leastIconSize)

        compact.contentMeasured(height: 440)
        var fit = AboutFit(resuming: compact)
        #expect(fit.isCompact)
        #expect(fit.stackedExtra == compact.stackedExtra)
        fit.contentMeasured(height: 440)
        fit.pageChanged(to: CGSize(width: 640, height: 480))
        #expect(fit.isCompact)
        fit.pageChanged(to: CGSize(width: 640, height: 484))
        #expect(!fit.isCompact)
    }
}
