import AppKit
import Testing

/// The bottom bars keep each button on one line (STYLE_GUIDE → Translations:
/// "Short slots stay short"): in every language of the String Catalog, their
/// texts must fit the narrowest window or page. Measured as the bars lay
/// them out: the app's text sizes, a chip's padding on Liquid Glass (14 pt a
/// side, the wider), 8 pt between items, the bar's side margins.
@Suite("Bottom bars fit in every language")
struct BottomBarFitTests {
    /// One item of a bar: a text, as a chip (`chip`) or plain, and the room a
    /// chip's label adds itself (Continue and Done pad 6 pt a side).
    struct Item {
        let keys: [String] // a slot shows one of these (Later or Cancel): the widest counts
        var size: CGFloat = 14
        var weight: NSFont.Weight = .regular
        var chip = true
        var extra: CGFloat = 0
    }

    struct Bar: CustomTestStringConvertible {
        let name: String
        let width: CGFloat
        let margin: CGFloat
        let items: [Item]
        /// Items and spacers the bar's HStack lays out, for its gaps.
        let slots: Int
        var testDescription: String { name }
    }

    static let chipPadding: CGFloat = 14
    static let spacing: CGFloat = 8

    static let bars: [Bar] = [
        Bar(name: "Settings → Apps", width: 480, margin: 16, items: [
            Item(keys: ["Ignore Another App…"]), Item(keys: ["Remove"]), Item(keys: ["Reset List…"]),
        ], slots: 4),
        Bar(name: "Settings → Diagnostics", width: 480, margin: 16, items: [
            Item(keys: ["Updated as it happens."], size: 13, chip: false), Item(keys: ["Copy Report"]),
        ], slots: 3),
        Bar(name: "Welcome window, permissions", width: 540, margin: 20, items: [
            Item(keys: ["Back"]), Item(keys: ["Done"], weight: .semibold, extra: 12),
        ], slots: 3),
        Bar(name: "Add a Web App", width: 440, margin: 20, items: [
            Item(keys: ["Later", "Cancel"]), Item(keys: ["Continue"], weight: .semibold, extra: 12),
        ], slots: 3),
    ]

    /// Every key's value per language, English as the key.
    static let catalog: [String: [String: String]] = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appending(path: "Resources/Localization/Localizable.xcstrings")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: [String: Any]] else { return [:] }
        return strings.mapValues { entry in
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            return localizations.compactMapValues { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
        }
    }()

    static var languages: [String] {
        ["en"] + Set(catalog.values.flatMap(\.keys)).sorted()
    }

    static func width(of text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).size().width)
    }

    @Test("each bar's buttons fit on one line at its narrowest", arguments: bars)
    func fits(_ bar: Bar) {
        #expect(!Self.catalog.isEmpty, "the String Catalog wasn't found")
        let room = bar.width - 2 * bar.margin
        for language in Self.languages {
            let items = bar.items.map { item -> CGFloat in
                let text = item.keys.map { key in language == "en" ? key : Self.catalog[key]?[language] ?? key }
                let widest = text.map { Self.width(of: $0, size: item.size, weight: item.weight) }.max() ?? 0
                return widest + item.extra + (item.chip ? 2 * Self.chipPadding : 0)
            }
            let total = items.reduce(0, +) + CGFloat(bar.slots - 1) * Self.spacing
            #expect(total <= room, "\(bar.name) in \(language): \(Int(total)) pt for \(Int(room)) pt")
        }
    }

    @Test("every bar's texts are in the catalog")
    func keysExist() {
        for bar in Self.bars {
            for key in bar.items.flatMap(\.keys) {
                #expect(Self.catalog[key] != nil, "\(bar.name): “\(key)” isn't in the String Catalog")
            }
        }
    }
}
