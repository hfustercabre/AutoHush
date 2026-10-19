import Foundation
import Observation
import AutoHushKit

/// Settings → Sound Sources' list: a row for each app that played sound and
/// each ignored one, in the order the user chose, the search by name, the
/// selection (a click, ⌘ and ⇧, as in macOS's lists) and Remove, asked first
/// when an app is turned off. It reads the apps from `AppState` and the order
/// from `UserSettings`, and changes them there; `SettingsModel` owns it
/// (X20, the full check, 2026-10-19).
@MainActor
@Observable
final class AppListModel {
    /// One app in the list, and whether it is ignored.
    struct Row: Identifiable, Equatable {
        let source: AudioSource
        let isIgnored: Bool
        /// When it played, as a place in line: 0 played most recently. `nil`
        /// for an app ignored before it ever played.
        var playedRank: Int?
        var id: String { source.id }
    }

    /// How the apps are ordered; the most recent first unless the user
    /// chose otherwise.
    var order: AppListOrder { settings.state.listOrder }
    /// The apps that played sound, the most recent first, plus the ignored
    /// ones, in `order`. Ordered again only when the apps or the order
    /// changed, not each time a view reads them.
    var apps: [Row] {
        let seen = state.seenApps, ignored = state.ignoredApps, order = self.order
        if let last = orderedApps, last.seen == seen, last.ignored == ignored, last.order == order { return last.rows }
        let rows = Self.ordered(Self.rows(seen: seen, ignored: ignored), by: order)
        orderedApps = (seen, ignored, order, rows)
        return rows
    }
    /// The rows `apps` ordered last, and what from.
    @ObservationIgnored private var orderedApps: (seen: [AudioSource], ignored: [AudioSource], order: AppListOrder, rows: [Row])?
    /// The search: `nil` while it's closed. It's closed again each time
    /// Settings opens.
    var search: String?
    /// The apps whose names match the search, ignoring case and accents, in
    /// `order`; all of them while there's nothing to search for.
    var shownApps: [Row] {
        let query = search?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.source.name.localizedStandardContains(query) }
    }
    /// The apps selected, which Remove takes off the list: several at once,
    /// as in macOS's lists (the user, 2026-10-18).
    private(set) var selectedAppIDs: Set<String> = []
    /// The selected apps the list shows, in its order: the search may hide
    /// some, which stay selected but aren't removed.
    var selectedApps: [Row] { shownApps.filter { selectedAppIDs.contains($0.id) } }
    /// Where a ⇧-click selects from: the last row clicked without ⇧, or
    /// added or taken out from the keyboard.
    @ObservationIgnored private var selectionAnchor: String?
    /// What was selected besides it then. A ⇧-click adds its range to this,
    /// so a second one changes the range, as in macOS's lists, and keeps
    /// what was selected before.
    @ObservationIgnored private var selectionBesidesRange: Set<String> = []
    /// The apps the user asked to remove, while that's confirmed: one that's
    /// turned off, or several with one turned off at least. Empty otherwise.
    private(set) var appsAwaitingRemoval: [Row] = []
    /// Their names, kept while the confirmation closes (its title shows the
    /// name, or how many they are).
    private(set) var removalNames: [String] = []

    /// The apps that played sound and the ignored ones.
    @ObservationIgnored private let state: AppState
    /// The order, and where apps are forgotten.
    @ObservationIgnored private let settings: UserSettings

    init(state: AppState, settings: UserSettings) {
        self.state = state
        self.settings = settings
    }

    func setOrder(_ order: AppListOrder) {
        guard order != self.order else { return }
        settings.setListOrder(order)
    }

    // MARK: - Selection

    /// A click on an app, as in macOS's lists. Alone, it selects only that
    /// app, or unselects it when it's the only one the list shows selected.
    /// With ⌘, it adds the app or takes it out. With ⇧ (⌘ too), it selects
    /// every app shown from the last one clicked to this one, or adds this
    /// one when that one isn't shown.
    func click(on id: String, command: Bool = false, shift: Bool = false) {
        if shift {
            if let anchor = selectionAnchor, let range = shownRange(from: anchor, to: id) {
                selectedAppIDs = selectionBesidesRange.union(range)
            } else {
                selectionBesidesRange = selectedAppIDs
                selectionAnchor = id
                selectedAppIDs.insert(id)
            }
        } else if command {
            toggleSelection(of: id)
        } else if selectedApps.map(\.id) == [id] {
            clearSelection()
        } else {
            selectedAppIDs = [id]
            selectionAnchor = id
            selectionBesidesRange = []
        }
    }

    /// Adds the app to the selection, or takes it out: a ⌘-click, or Return
    /// or Space on the row, so the keyboard can select several too.
    func toggleSelection(of id: String) {
        if selectedAppIDs.remove(id) == nil { selectedAppIDs.insert(id) }
        selectionAnchor = id
        selectionBesidesRange = selectedAppIDs
    }

    /// Settings closed: a selection doesn't outlive it.
    func clearSelection() {
        selectedAppIDs = []
        selectionAnchor = nil
        selectionBesidesRange = []
    }

    /// The IDs of the apps shown from `anchor` to `id`, both included, in
    /// the list's order; `nil` when either isn't shown.
    private func shownRange(from anchor: String, to id: String) -> [String]? {
        let ids = shownApps.map(\.id)
        guard let start = ids.firstIndex(of: anchor), let end = ids.firstIndex(of: id) else { return nil }
        return Array(ids[min(start, end)...max(start, end)])
    }

    // MARK: - Removing

    /// Remove: takes the selected apps the list shows off it. Those that
    /// pause the music go at once; one that's turned off would pause it
    /// again, so that's asked first (`appsAwaitingRemoval`), once for all.
    func removeSelected() {
        let rows = selectedApps
        if rows.contains(where: \.isIgnored) {
            askToRemove(rows)
        } else {
            rows.forEach(takeOff)
        }
    }

    /// Takes this app off the list, whatever is selected; asked first when
    /// it's turned off.
    func remove(_ row: Row) {
        if row.isIgnored {
            askToRemove([row])
        } else {
            takeOff(row)
        }
    }

    private func askToRemove(_ rows: [Row]) {
        removalNames = rows.map(\.source.name)
        appsAwaitingRemoval = rows
    }

    /// Remove from List, on an app's row: the whole selection when the app
    /// is one of several selected, as in Finder (the full check, 2026-10-18);
    /// else that app alone.
    func removeFromList(_ row: Row) {
        if selectedAppIDs.contains(row.id), selectedApps.count > 1 {
            removeSelected()
        } else {
            remove(row)
        }
    }

    /// The apps asked about are removed after all.
    func confirmRemoval() {
        let rows = appsAwaitingRemoval
        appsAwaitingRemoval = []
        rows.forEach(takeOff)
    }

    /// The confirmation closed without removing them.
    func cancelRemoval() { appsAwaitingRemoval = [] }

    private func takeOff(_ row: Row) {
        settings.forget(row.source)
        selectedAppIDs.remove(row.id)
        selectionBesidesRange.remove(row.id)
        if selectionAnchor == row.id { selectionAnchor = nil }
    }

    // MARK: - The rows

    /// A row for each app that played audio, ranked the most recent first,
    /// then one for each ignored app that never played.
    static func rows(seen: [AudioSource], ignored: [AudioSource]) -> [Row] {
        let ignoredIDs = Set(ignored.map(\.id))
        var rows = seen.enumerated().map {
            Row(source: $0.element, isIgnored: ignoredIDs.contains($0.element.id), playedRank: $0.offset)
        }
        for app in ignored where !rows.contains(where: { $0.id == app.id }) {
            rows.append(Row(source: app, isIgnored: true))
        }
        return rows
    }

    /// The rows in `order`. Ties, and the apps that never played, go by name;
    /// for a reversed On/Off order, only the groups swap.
    static func ordered(_ rows: [Row], by order: AppListOrder) -> [Row] {
        let name = { (row: Row) in row.source.name.localizedLowercase }
        switch order.criterion {
        case .lastPlayed:
            let rank = { (row: Row) in row.playedRank ?? .max }
            let list = rows.sorted { (rank($0), name($0), $0.id) < (rank($1), name($1), $1.id) }
            return order.isReversed ? list.reversed() : list
        case .name:
            let list = rows.sorted { (name($0), $0.id) < (name($1), $1.id) }
            return order.isReversed ? list.reversed() : list
        case .state:
            let group = { (row: Row) in row.isIgnored != order.isReversed ? 1 : 0 }
            return rows.sorted { (group($0), name($0), $0.id) < (group($1), name($1), $1.id) }
        }
    }
}
