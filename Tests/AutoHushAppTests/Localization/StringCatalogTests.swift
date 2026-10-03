import Foundation
import Testing

/// The String Catalogs in Resources/Localization/, AutoHush's text in every language.
/// `Scripts/build-app.sh` adds the strings the code uses to
/// Localizable.xcstrings and compiles both catalogs into the app.
@Suite("String catalogs")
struct StringCatalogTests {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Localization
        .deletingLastPathComponent() // AutoHushAppTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // the package
        .appending(path: "Resources")
    private static let catalogs = resources.appending(path: "Localization")

    @Test("every translation keeps its text's placeholders", arguments: ["Localizable", "InfoPlist"])
    func placeholders(table: String) throws {
        let catalog = try StringCatalog(contentsOf: Self.catalogs.appending(path: "\(table).xcstrings"))
        for (key, entry) in catalog.strings {
            let localizations = entry.localizations ?? [:]
            // The key is the English text, unless English has a text of its own.
            let expected = Self.placeholders(in: localizations[catalog.sourceLanguage]?.stringUnit?.value ?? key)
            for (language, localization) in localizations {
                for (text, isForm) in localization.texts {
                    let found = Self.placeholders(in: text)
                    // A plural form may leave out the number ("one app"), but never changes or adds one.
                    let keepsThem = isForm ? found.allSatisfy { expected[$0.key] == $0.value } : found == expected
                    #expect(keepsThem, "\(language) text of “\(key)”: \(text)")
                }
            }
        }
    }

    @Test("Info.plist's texts are in the InfoPlist catalog, word for word")
    func infoPlistTexts() throws {
        let data = try Data(contentsOf: Self.resources.appending(path: "Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let shown = plist.compactMapValues { $0 as? String }
            .filter { $0.key.hasSuffix("UsageDescription") || $0.key == "NSHumanReadableCopyright" }
        let catalog = try StringCatalog(contentsOf: Self.catalogs.appending(path: "InfoPlist.xcstrings"))

        #expect(Set(catalog.strings.keys) == Set(shown.keys))
        for (key, text) in shown {
            #expect(catalog.strings[key]?.localizations?[catalog.sourceLanguage]?.stringUnit?.value == text, "\(key)")
        }
    }

    /// The placeholders of a format string by argument position: "%@ and %lld"
    /// and "%2$lld … %1$@" both give [1: "@", 2: "lld"].
    private static func placeholders(in text: String) -> [Int: String] {
        var found: [Int: String] = [:]
        var next = 1
        let specifier = /%(?:(\d+)\$)?[-+ 0]*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfFeEgGcCsSpaA])/
        for match in text.replacing("%%", with: "").matches(of: specifier) {
            let position = match.1.flatMap { Int($0) } ?? next
            found[position] = String(match.2 ?? "") + match.3
            next = position + 1
        }
        return found
    }
}

/// The parts of a String Catalog (.xcstrings) these tests read.
private struct StringCatalog: Decodable {
    struct Entry: Decodable {
        var localizations: [String: Localization]?
    }

    struct Localization: Decodable {
        struct StringUnit: Decodable {
            var value: String
        }

        var stringUnit: StringUnit?
        /// By kind ("plural", "device"), then by case ("one", "other", "mac"…).
        var variations: [String: [String: Localization]]?

        /// Its text, and the text of each plural or device form.
        var texts: [(text: String, isForm: Bool)] {
            let forms = (variations ?? [:]).values.flatMap(\.values).flatMap(\.texts).map { ($0.text, true) }
            return (stringUnit.map { [($0.value, false)] } ?? []) + forms
        }
    }

    var sourceLanguage: String
    var strings: [String: Entry]

    init(contentsOf url: URL) throws {
        self = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}
