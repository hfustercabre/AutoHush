import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit

/// The choices (`ChoiceChips`, AppKit's segmented control) set Settings'
/// least width in the app's language (the user, 2026-10-17: "make the minimum
/// width respect the content, check all languages"): since the update choice
/// became a pop-up menu (A4, 2026-10-26), only Fine-Tuning's AntiDot mode's
/// ways. Measured in every language of the String Catalog: the room they
/// need stays within a window of a sensible size, so a much longer
/// translation shows here first. The menu has no choices since A1.
@Suite("Choices fit in every language")
@MainActor
struct ChoiceFitTests {
    static let detection = ["What apps tell macOS", "Open audio streams only"]

    private func titles(_ keys: [String], in language: String) -> [String] {
        keys.map { language == "en" ? $0 : BottomBarFitTests.catalog[$0]?[language] ?? $0 }
    }

    @Test("Settings' page fits AntiDot mode's ways within 700 pt", arguments: BottomBarFitTests.languages)
    func fits(_ language: String) {
        #expect(!BottomBarFitTests.catalog.isEmpty, "the String Catalog wasn't found")
        let page = ChoiceChips<Never>.fittingWidth(titles(Self.detection, in: language)) + 60
        #expect(page <= 700, "Settings: \(Int(page)) pt")
    }

    @Test("in the app's language, Settings' least width leaves AntiDot mode's ways their room; the menu is 345 pt")
    func leastWidths() {
        let page = SettingsWindowController.minimumSize.width - SettingsWindowController.sidebarWidth
        #expect(page >= ChoiceChips<Never>.fittingWidth(DetectionMethod.antiDotWays.map(\.title)) + 60)
        #expect(SettingsWindowController.maximumSize.width >= SettingsWindowController.minimumSize.width)
        #expect(menuContentWidth == 345)
    }
}
