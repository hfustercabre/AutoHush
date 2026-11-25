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

    /// The catalog of a table (Resources/Localization/<table>.xcstrings).
    init(table: String) throws {
        try self.init(contentsOf: PackagePaths.catalogs.appending(path: "\(table).xcstrings"))
    }

    /// Every catalog's table, by name: InfoPlist, AppShortcuts and the app's own.
    static let tables: [String] = ((try? FileManager.default.contentsOfDirectory(at: PackagePaths.catalogs,
                                                                                includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.pathExtension == "xcstrings" }
        .map { $0.deletingPathExtension().lastPathComponent }
        .sorted()

    /// The app's own text, a table per area (Localizable: the words several
    /// share): every table but the two macOS reads by name.
    static let appTables = tables.filter { $0 != "InfoPlist" && $0 != "AppShortcuts" }

    /// The app's tables as one, each key's entry from the table that has it.
    static func app() throws -> [String: Entry] {
        try appTables.reduce(into: [:]) { all, table in
            all.merge(try StringCatalog(table: table).strings) { first, _ in first }
        }
    }
}
