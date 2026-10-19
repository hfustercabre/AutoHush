import Foundation

/// The parts of a String Catalog (.xcstrings) the tests read.
struct StringCatalog: Decodable {
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
