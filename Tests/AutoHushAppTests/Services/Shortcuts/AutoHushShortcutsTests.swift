import Foundation
import Testing
@testable import AutoHushApp

@Suite("AutoHushShortcuts")
struct AutoHushShortcutsTests {
    /// The phrases' catalog, which Siri, Spotlight and Shortcuts read.
    private static let appShortcuts = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Shortcuts
        .deletingLastPathComponent() // Services
        .deletingLastPathComponent() // AutoHushAppTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the package
        .appending(path: "Resources/Localization/AppShortcuts.xcstrings")

    @Test("the app offers two ready-made shortcuts: turn Auto-Pause off, turn it on")
    func twoShortcuts() {
        #expect(AutoHushShortcuts.appShortcuts.count == 2)
    }

    @Test("every phrase names the app, in English and in every translation: Siri requires it")
    func phrasesNameTheApp() throws {
        let catalog = try StringCatalog(contentsOf: Self.appShortcuts)
        // The two phrases the provider's source holds, word for word.
        #expect(Set(catalog.strings.keys) == [
            "Turn off Auto-Pause in ${applicationName}",
            "Turn on Auto-Pause in ${applicationName}",
        ])
        for (key, entry) in catalog.strings {
            #expect(key.contains("${applicationName}"), "“\(key)”")
            for (language, localization) in entry.localizations ?? [:] {
                for (text, _) in localization.texts {
                    #expect(text.contains("${applicationName}"), "\(language) text of “\(key)”: \(text)")
                }
            }
        }
    }
}
