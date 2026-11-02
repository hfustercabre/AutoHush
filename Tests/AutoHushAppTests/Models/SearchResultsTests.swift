import AppKit
import Testing
@testable import AutoHushApp

/// What VoiceOver hears once typing in a search pauses (A14, 2026-11-01).
@Suite("A search's results, as VoiceOver hears them")
struct SearchResultsTests {
    @Test("how many items the search shows, or the list's own words for none")
    func announcement() {
        #expect(SearchResults(count: 0, noMatch: "No apps match “zz”.").announcement == "No apps match “zz”.")
        #expect(SearchResults(count: 3, noMatch: "No apps match “zz”.").announcement == "3 results")
    }

    @Test("the count has English plural forms: “1 result”, “2 results”")
    func pluralForms() throws {
        let catalog = try StringCatalog(contentsOf: PackagePaths.catalogs.appending(path: "Localizable.xcstrings"))
        let forms = try #require(catalog.strings["%lld results"]?.localizations?["en"]?.variations?["plural"])
        #expect(forms["one"]?.stringUnit?.value == "%lld result")
        #expect(forms["other"]?.stringUnit?.value == "%lld results")
    }

    @Test("it goes out at low priority, after what VoiceOver is saying, and a typing pause is half a second")
    @MainActor
    func priorityAndDelay() {
        let info = announcementInfo("3 results", priority: .low)
        #expect(info[.announcement] as? String == "3 results")
        #expect(info[.priority] as? Int == NSAccessibilityPriorityLevel.low.rawValue)
        #expect(SearchField.resultsDelay == .milliseconds(500))
    }
}
