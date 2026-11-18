import Foundation
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
}
