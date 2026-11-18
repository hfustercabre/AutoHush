import Foundation
import SwiftUI
import Testing
@testable import AutoHushApp

@Suite("RightToLeftLayout")
struct RightToLeftLayoutTests {
    @Test("Arabic and Hebrew read right to left; every other language AutoHush comes in, and none, left to right",
          arguments: [("ar", true), ("he", true), ("en", false), ("de", false), ("ja", false), ("zh-Hant", false)])
    func directions(_ language: String, _ rightToLeft: Bool) {
        #expect(RightToLeftLayout.readsRightToLeft(language) == rightToLeft)
        #expect(!RightToLeftLayout.readsRightToLeft(nil))
    }

    @Test("run in Arabic or Hebrew, AutoHush registers AppKit's right-to-left direction (a default only: a value set by hand wins); run in another language, nothing",
          arguments: [(["ar", "en"], true), (["he"], true), (["en", "ar"], false), ([], false)])
    func registers(_ preferred: [String], _ registered: Bool) {
        let values = RightToLeftLayout.defaults(preferred: preferred)
        #expect((values[RightToLeftLayout.key] as? Bool) == (registered ? true : nil))
        #expect(values.count == (registered ? 1 : 0))
    }

    @Test("← and → on a slider or a row of chips step the way they point, as macOS's own do: left to right, → goes up the values (or to the next chip); right to left (Arabic, Hebrew), where the minimum or the first chip is on the right, → goes back",
          arguments: [(LayoutDirection.leftToRight, 1, 1), (.leftToRight, -1, -1), (.rightToLeft, 1, -1), (.rightToLeft, -1, 1)])
    func arrows(_ layout: LayoutDirection, _ arrow: Int, _ step: Int) {
        #expect(RightToLeftLayout.arrowStep(arrow, in: layout) == step)
    }
}
