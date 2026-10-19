import AppKit
import Testing
@testable import AutoHushApp

/// The bottom bars keep each button on one line (STYLE_GUIDE → Translations:
/// "Short slots stay short"): in every language of the String Catalog, their
/// texts must fit the narrowest window or page. Measured as the bars lay
/// them out: the app's text sizes, a chip's padding on Liquid Glass (14 pt a
/// side, the wider), 8 pt between items, the bar's side margins. The line
/// under a player's name on its tile (`PlayerTiles`) is measured the same
/// way, as a bar of one text. The fonts are those of the macOS the tests run
/// on: run on the latest, as renders are, a text near its limit is judged
/// as the latest macOS draws it.
@Suite("Bottom bars fit in every language")
struct BottomBarFitTests {
    /// One item of a bar: a text, as a chip (`chip`) or plain, and the room a
    /// chip's label adds itself (Continue and Done pad 6 pt a side); a switch
    /// is its width alone, with no text.
    struct Item {
        let keys: [String] // a slot shows one of these (Later or Cancel): the widest counts
        var size: CGFloat = 14
        var weight: NSFont.Weight = .regular
        var chip = true
        var extra: CGFloat = 0
    }

    struct Bar: CustomTestStringConvertible {
        let name: String
        /// The narrowest the window or page gets, from its own constants.
        let width: @MainActor @Sendable () -> CGFloat
        let margin: CGFloat
        let items: [Item]
        /// Items and spacers the bar's HStack lays out, for its gaps.
        let slots: Int
        var testDescription: String { name }
    }

    static let chipPadding: CGFloat = 14
    static let spacing: CGFloat = 8

    static let bars: [Bar] = [
        Bar(name: "Settings → Sound Sources", width: { settingsPage }, margin: 20, items: [
            Item(keys: ["Ignore Another App…"]), Item(keys: ["Remove"]), Item(keys: ["Reset List…"]),
        ], slots: 4),
        Bar(name: "Settings → Diagnostics", width: { settingsPage }, margin: 20, items: [
            // "Updated as it happens." is at the top of the page; "Copied" shows on the button.
            Item(keys: ["Show Logs…"]), Item(keys: ["Copy Report", "Copied"]),
        ], slots: 3),
        Bar(name: "Welcome window, permissions", width: { PlayerChooserView.width }, margin: 20, items: [
            Item(keys: ["Back"]), Item(keys: ["Done"], weight: .semibold, extra: 12),
        ], slots: 3),
        Bar(name: "Add a Web App", width: { AddWebAppView.width }, margin: 20, items: [
            Item(keys: ["Later", "Cancel"]), Item(keys: ["Continue"], weight: .semibold, extra: 12),
        ], slots: 3),
        Bar(name: "Choose an App", width: { AppChooserView.width }, margin: 20, items: [
            Item(keys: ["Other App…"]), Item(keys: ["Cancel"]), Item(keys: ["Choose"], weight: .semibold, extra: 12),
        ], slots: 4),
        Bar(name: "The check's warning window", width: { CheckWarningView.width }, margin: 20, items: [
            Item(keys: ["Cancel"]), Item(keys: ["Start the Check"], weight: .semibold, extra: 12),
        ], slots: 3),
        Bar(name: "Logs window", width: { LogsWindowController.minimumSize.width }, margin: 20, items: [
            Item(keys: [], chip: false, extra: 36), // the switch
            Item(keys: ["Follow new entries"], size: 13, chip: false), Item(keys: ["Save…"]), Item(keys: ["Copy Logs", "Copied"]),
        ], slots: 5),
    ] + ["Click to add", "Not installed", "Not in AntiDot", "Muted only"].map {
        Bar(name: "A player's tile: \($0)", width: { tileLine }, margin: 0, items: [Item(keys: [$0], size: 11, chip: false)], slots: 1)
    } + [ // a HeadingBadge: semibold, 6 pt of capsule a side
        Bar(name: "A player's tile: Untested", width: { tileLine }, margin: 0,
            items: [Item(keys: ["Untested"], size: 11, weight: .semibold, chip: false, extra: 12)], slots: 1),
    ]

    /// Settings' narrowest page: the window at its least, less the sidebar.
    @MainActor static var settingsPage: CGFloat {
        SettingsWindowController.minimumSize.width - SettingsWindowController.sidebarWidth
    }

    /// The room for the line under a player's name on its tile, on Settings'
    /// narrowest page (16 pt margins): three tiles a row, 8 pt apart, in a
    /// Liquid Glass card (14 pt padding, the wider); in each, 6 pt in, the
    /// 24 pt icon, 8 pt, the text, 6 pt in.
    @MainActor static var tileLine: CGFloat { (settingsPage - 2 * 16 - 2 * 14 - 2 * 8) / 3 - (6 + 24 + 8 + 6) }

    /// Every key's value per language, English as the key.
    static let catalog: [String: [String: String]] = {
        guard let catalog = try? StringCatalog(contentsOf: PackagePaths.catalogs.appending(path: "Localizable.xcstrings")) else { return [:] }
        return catalog.strings.mapValues { ($0.localizations ?? [:]).compactMapValues { $0.stringUnit?.value } }
    }()

    static var languages: [String] {
        ["en"] + Set(catalog.values.flatMap(\.keys)).sorted()
    }

    static func width(of text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).size().width)
    }

    @Test("each bar's buttons fit on one line at its narrowest", arguments: bars)
    @MainActor func fits(_ bar: Bar) {
        #expect(!Self.catalog.isEmpty, "the String Catalog wasn't found")
        let room = bar.width() - 2 * bar.margin
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
