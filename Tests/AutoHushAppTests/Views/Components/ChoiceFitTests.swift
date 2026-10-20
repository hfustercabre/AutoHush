import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit

/// The choices (`ChoiceChips`, AppKit's segmented control) set Settings' and
/// the menu's least width in the app's language (the user, 2026-10-17: "make
/// the minimum width respect the content, check all languages"). Measured in
/// every language of the String Catalog: the room each needs stays within a
/// window and a menu of a sensible size, so a much longer translation shows
/// here first.
@Suite("Choices fit in every language")
@MainActor
struct ChoiceFitTests {
    static let updates = ["Notify me", "Download it and notify me", "Install it automatically"]
    static let detection = ["What apps tell macOS", "Open audio streams only"]

    private func titles(_ keys: [String], in language: String) -> [String] {
        keys.map { language == "en" ? $0 : BottomBarFitTests.catalog[$0]?[language] ?? $0 }
    }

    @Test("Settings' page fits each choice within 700 pt, and the menu AntiDot mode's ways within 440 pt",
          arguments: BottomBarFitTests.languages)
    func fits(_ language: String) {
        #expect(!BottomBarFitTests.catalog.isEmpty, "the String Catalog wasn't found")
        let page = [Self.updates, Self.detection].map { ChoiceChips<Never>.fittingWidth(titles($0, in: language)) }.max()! + 60
        #expect(page <= 700, "Settings: \(Int(page)) pt")
        let menu = ChoiceChips<Never>.fittingWidth(titles(Self.detection, in: language), size: .small) + 36
        #expect(menu <= 440, "the menu: \(Int(menu)) pt")
    }

    @Test("in the app's language, Settings' least width and the menu's width leave the choices their room")
    func leastWidths() {
        let page = SettingsWindowController.minimumSize.width - SettingsWindowController.sidebarWidth
        #expect(page >= ChoiceChips<Never>.fittingWidth([AutomaticUpdates.notify, .download, .install].map(\.title)) + 60)
        #expect(page >= ChoiceChips<Never>.fittingWidth(DetectionMethod.antiDotWays.map(\.title)) + 60)
        #expect(SettingsWindowController.maximumSize.width >= SettingsWindowController.minimumSize.width)
        #expect(menuContentWidth >= ChoiceChips<Never>.fittingWidth(DetectionMethod.antiDotWays.map(\.title), size: .small) + 36)
        #expect(menuContentWidth >= 345)
    }
}
