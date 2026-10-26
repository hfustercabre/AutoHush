import Foundation
import Testing

/// The String Catalogs in Resources/Localization/, AutoHush's text in every language.
/// `Scripts/build-app.sh` adds the strings the code uses to
/// Localizable.xcstrings and compiles every catalog into the app.
@Suite("String catalogs")
struct StringCatalogTests {
    private static let resources = PackagePaths.root.appending(path: "Resources")
    private static let catalogs = PackagePaths.catalogs

    @Test("every translation keeps its text's placeholders", arguments: ["Localizable", "InfoPlist", "AppShortcuts"])
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

    @Test("apostrophes are curly, in English and every translation, as macOS writes them", arguments: ["Localizable", "InfoPlist", "AppShortcuts"])
    func curlyApostrophes(table: String) throws {
        let catalog = try StringCatalog(contentsOf: Self.catalogs.appending(path: "\(table).xcstrings"))
        for (key, entry) in catalog.strings {
            #expect(!key.contains("'"), "“\(key)”")
            for (language, localization) in entry.localizations ?? [:] {
                for (text, _) in localization.texts {
                    #expect(!text.contains("'"), "\(language) text of “\(key)”: \(text)")
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

    /// A placeholder: its position, flags, width, precision, length and
    /// conversion, a digit being any character with a numeric value, as a
    /// Swift Regex's `\d` reads it. Made once: a Swift Regex took 3.5 s
    /// over the catalogs' texts in a debug build, this a tenth of a second.
    private static let specifier = try! NSRegularExpression(
        pattern: #"%(?:([\p{nt=De}\p{nt=Di}\p{nt=Nu}]+)\$)?[-+ 0]*[\p{nt=De}\p{nt=Di}\p{nt=Nu}]*(?:\.[\p{nt=De}\p{nt=Di}\p{nt=Nu}]+)?"#
            + #"(hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfFeEgGcCsSpaA])"#
    )

    /// The placeholders of a format string by argument position: "%@ and %lld"
    /// and "%2$lld … %1$@" both give [1: "@", 2: "lld"]. Read character by
    /// character, as a Swift Regex reads: a character of several scalars (a
    /// letter and its accent) is read as one, a digit with no value of its
    /// own (½) when it's a number, else one that's nothing here (U+FFFC).
    private static func placeholders(in text: String) -> [Int: String] {
        guard text.utf8.contains(UInt8(ascii: "%")) else { return [:] }
        var scalars = String.UnicodeScalarView()
        for character in text {
            let single = character.unicodeScalars.count == 1 ? character.unicodeScalars.first : nil
            scalars.append(single ?? (character.isNumber ? "½" : "\u{FFFC}"))
        }
        let flat = String(scalars).replacingOccurrences(of: "%%", with: "")
        var found: [Int: String] = [:]
        var next = 1
        for match in specifier.matches(in: flat, range: NSRange(flat.startIndex..., in: flat)) {
            func group(_ index: Int) -> String { Range(match.range(at: index), in: flat).map { String(flat[$0]) } ?? "" }
            let position = Int(group(1)) ?? next
            found[position] = group(2) + group(3)
            next = position + 1
        }
        return found
    }
}
