import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AutoHushKit

/// Settings → Sound Sources: which apps pause the music, as a section of
/// macOS's grouped form, each with its switch as in the menu's "Playing
/// Now", in the order the user chose; a magnifier opens a search by name in
/// place of the heading. A click selects
/// an app, ⌘-click and ⇧-click several, as in macOS's lists, and Remove
/// takes them off the list (asking first when one is turned off, which then
/// pauses the music again). The page fills the window: the list scrolls
/// between the heading and the buttons.
struct SoundSourcesSettingsView: View {
    let model: SettingsModel
    @State private var confirmingReset = false

    var body: some View {
        page
        // Settings' window is kept when closed: a selection doesn't outlive it.
        .onDisappear { model.clearSelection() }
    }

    /// The heading, the list that scrolls, and the buttons.
    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The list as a section of macOS's grouped form, its sort and search over it.
            Form {
                Card(heading: AnyView(header)) {
                    if model.apps.isEmpty {
                        Text("Apps appear here once they have played audio.", comment: "Settings → Sound Sources, while the list is empty")
                            .foregroundStyle(.appSecondary)
                    } else if model.shownApps.isEmpty, let search = model.appSearch {
                        Text(verbatim: String(localized: "No apps match “\(search)”.",
                                              comment: "Settings → Sound Sources, when the search finds nothing; %@ is what was typed"))
                            .foregroundStyle(.appSecondary)
                    }
                    ForEach(Array(model.shownApps.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { CardDivider() }
                        SoundSourceRow(model: model, row: row)
                    }
                } footer: {
                    Text("Turn an app off to keep your player playing while it makes sound. Select apps to remove them from the list.",
                         comment: "Settings → Sound Sources, under the list; “Select” as in clicking apps in the list (⌘-click or ⇧-click selects several)")
                        .captionStyle()
                }
                .animation(.default, value: model.apps)
            }
            .formStyle(.grouped)
            .environment(\.cardsAreFormSections, true)
            // Each button on one line, in every language: three of them leave
            // little room.
            BottomBar {
                Button { IgnoreAppsPicker.run { model.settings.setIgnored($0, true) } } label: {
                    Text(verbatim: IgnoreAppsPicker.title)
                }
                    .buttonStyle(.chip)
                    .fixedSize()
                Button { model.removeSelected() } label: { Text(verbatim: PlayerAlerts.removeTitle) }
                    .buttonStyle(.chip)
                    .fixedSize()
                    .disabled(model.selectedApps.isEmpty)
                Spacer(minLength: 0)
                Button(role: .destructive) { confirmingReset = true } label: {
                    Text("Reset List…", comment: "Settings → Sound Sources: button that asks to forget every app in the list")
                }
                    .buttonStyle(.chip)
                    .fixedSize()
                    .disabled(model.apps.isEmpty)
            }
            // The arrow keys reach them after the list, however it's scrolled.
            .environment(\.highlightBand, .bottom)
        }
        .confirmationDialog(Text("Reset the list of apps?", comment: "Settings → Sound Sources: title of the confirmation for Reset List"),
                            isPresented: $confirmingReset) {
            Button(role: .destructive) { model.settings.forgetAll() } label: {
                Text("Reset List", comment: "Settings → Sound Sources: confirms forgetting every app in the list")
            }
        } message: {
            Text("Every app is removed, and apps you turned off will pause your player again. Apps reappear as they play audio.",
                 comment: "Settings → Sound Sources: what Reset List does, in its confirmation")
        }
        .confirmationDialog(Text(verbatim: Self.removalTitle(names: model.removalNames)),
                            isPresented: Binding(get: { !model.appsAwaitingRemoval.isEmpty }, set: { if !$0 { model.cancelRemoval() } }),
                            presenting: model.appsAwaitingRemoval.isEmpty ? nil : model.appsAwaitingRemoval) { _ in
            Button(role: .destructive) { model.confirmRemoval() } label: { Text(verbatim: PlayerAlerts.removeTitle) }
        } message: { rows in
            Text(verbatim: Self.removalMessage(rows))
        }
    }

    /// The removal's confirmation's message: the app turned off by its name
    /// when only one of those asked about is (the full check, 2026-10-18),
    /// else "some of them".
    static func removalMessage(_ rows: [SettingsModel.AppRow]) -> String {
        let off = rows.filter(\.isIgnored)
        guard off.count > 1 else {
            let name = (off.first ?? rows.first)?.source.name ?? ""
            return String(localized: "\(name) is turned off now. Removed from the list, it pauses your player again when it plays.",
                          comment: "Settings → Sound Sources: what removing an app that's turned off does, in its confirmation; %@ is the app")
        }
        return String(localized: "Some of them are turned off now. Removed from the list, they pause your player again when they play.",
                      comment: "Settings → Sound Sources: what removing several selected apps does when one of them at least is turned off, in its confirmation")
    }

    /// The confirmation's title: the app's name for one, how many for several.
    static func removalTitle(names: [String]) -> String {
        names.count == 1
            ? String(localized: "Remove \(names[0]) from the list?",
                     comment: "Settings → Sound Sources: title of the confirmation for removing an app that's turned off; %@ is the app")
            : String(localized: "Remove \(names.count) apps from the list?",
                     comment: "Settings → Sound Sources: title of the confirmation for removing several selected apps, one of them at least turned off; %lld is how many (2 or more)")
    }

    /// The heading, or the search while it's open, then "Sort by" with the
    /// order's pop-up, an arrow that reverses it, and the magnifier.
    private var header: some View {
        let order = model.appListOrder
        return HStack(spacing: 6) {
            if model.appSearch != nil {
                // A closing field hands back its text as it loses focus:
                // only an open search takes it.
                SearchField(text: Binding(
                    get: { model.appSearch ?? "" },
                    set: { text in if model.appSearch != nil { model.appSearch = text } }
                ), focusesOnAppear: true) {
                    model.appSearch = nil
                }
                .padding(.trailing, 10)
            } else {
                SectionHeading(Text("Pauses Playback", comment: "Settings → Sound Sources: heading of the list of apps that pause your player while they play"), isFirst: true)
                Spacer()
            }
            Self.sortByTitle
                .font(.appCaption)
                .foregroundStyle(.appSecondary)
                .fixedSize() // on one line, in every language
                .accessibilityHidden(true) // the pop-up says it, as its label
            Picker(selection: Binding(
                get: { order.criterion },
                set: { model.setAppListOrder(AppListOrder(criterion: $0)) }
            )) {
                ForEach(AppListOrder.Criterion.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Self.sortByTitle
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .buttonStyle(.borderless)
            .fixedSize()
            // ← and → choose the order, while the arrow keys' highlight is on it.
            .modifier(Highlightable(cornerRadius: 6, outset: 3, adjust: { step in
                if let criterion = AppListOrder.Criterion.allCases.stepping(from: model.appListOrder.criterion, by: step) {
                    model.setAppListOrder(AppListOrder(criterion: criterion))
                }
            }))
            IconChipButton(
                symbol: order.isReversed ? "arrow.up" : "arrow.down",
                label: Text("Reverse order", comment: "Settings → Sound Sources: the arrow that reverses the apps' order"),
                help: Text(verbatim: String(localized: "\(order.directionTitle). Click to reverse the order.",
                                            comment: "Settings → Sound Sources, the arrow beside Sort by; %@ is the order now, e.g. “Newest first”"))
            ) {
                model.setAppListOrder(AppListOrder(criterion: order.criterion, isReversed: !order.isReversed))
            }
            .accessibilityValue(Text(verbatim: order.directionTitle))
            if model.appSearch == nil {
                IconChipButton(symbol: "magnifyingglass",
                               label: Text("Search by name", comment: "The magnifier that opens a search")) {
                    model.appSearch = ""
                }
                .disabled(model.apps.isEmpty)
            }
        }
    }

    /// Before the order's pop-up, and its name for VoiceOver.
    private static var sortByTitle: Text {
        Text("Sort by", comment: "Settings → Sound Sources, before the pop-up that orders the apps")
    }
}

extension AppListOrder.Criterion {
    /// Its name in Settings → Sound Sources' Sort by pop-up.
    var title: String {
        switch self {
        case .lastPlayed: String(localized: "Last Played", comment: "Settings → Sound Sources, Sort by: the app that played most recently first")
        case .name:       String(localized: "Name", comment: "Settings → Sound Sources, Sort by: alphabetically")
        case .state:      String(localized: "On/Off", comment: "Settings → Sound Sources, Sort by: apps that pause your player first, then the ignored ones")
        }
    }
}

extension AppListOrder {
    /// Which way round it goes, in its criterion's words, e.g. "Newest first".
    var directionTitle: String {
        switch (criterion, isReversed) {
        case (.lastPlayed, false): String(localized: "Newest first", comment: "Settings → Sound Sources: the order, the app that played last first")
        case (.lastPlayed, true):  String(localized: "Oldest first", comment: "Settings → Sound Sources: the order, the app that played longest ago first")
        case (.name, false):       String(localized: "A to Z", comment: "Settings → Sound Sources: the order, alphabetical")
        case (.name, true):        String(localized: "Z to A", comment: "Settings → Sound Sources: the order, reverse alphabetical")
        case (.state, false):      String(localized: "Apps that pause playback first", comment: "Settings → Sound Sources: the order, switched-on apps first")
        case (.state, true):       String(localized: "Ignored apps first", comment: "Settings → Sound Sources: the order, switched-off apps first")
        }
    }
}

/// An app in Settings → Sound Sources: its icon and name, whether it pauses
/// the music, and its switch. A click selects the row anywhere but on the
/// switch, which keeps its own clicks, ⌘ and ⇧ as in macOS's lists; from
/// the keyboard, Space adds the row in focus to the selection or takes it
/// out (Tab reaches it with keyboard navigation on), so several can be
/// removed too. The arrow keys and the pointer highlight it, as Settings'
/// other rows.
private struct SoundSourceRow: View {
    let model: SettingsModel
    let row: SettingsModel.AppRow
    @FocusState private var rowFocused: Bool
    @FocusState private var switchFocused: Bool
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: AppIcon.image(for: row.source, players: model.playerOptions, size: 24))
                    .resizable()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                RowTitle(
                    Text(verbatim: row.source.name),
                    subtitle: Text(verbatim: row.isIgnored ? SourceSwitchRow.ignoredLabel
                                   : PlayerOption.interruptsLabel(mutes: model.chosenPlayer?.pausesByMuting == true))
                )
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                let keys = NSEvent.modifierFlags
                model.click(on: row.id, command: keys.contains(.command), shift: keys.contains(.shift))
            }
            Toggle(isOn: Binding(
                get: { !row.isIgnored },
                set: { model.settings.setIgnored(row.source, !$0) }
            )) {
                Text(verbatim: row.source.name)
            }
            .toggleStyle(PillToggleStyle())
            .focused($switchFocused)
            .focusEffectDisabled(keyboard != nil)
        }
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6).fill(.selectedRowFill).padding(.horizontal, -6).padding(.vertical, -4)
            }
        }
        .contentShape(Rectangle())
        .focusable(interactions: .activate) // as a button: Tab, not a click, gives it focus
        .focused($rowFocused)
        .focusEffectDisabled(keyboard != nil) // the row's tint shows it
        // The arrow keys and the pointer highlight it, its tint as far out as
        // the selection's; Return or Space adds it to the selection or takes
        // it out.
        .highlightableRow(isFocused: rowFocused || switchFocused, cornerRadius: 6, vertical: 4,
                          press: { model.toggleSelection(of: row.id) })
        .onKeyPress(.space) {
            model.toggleSelection(of: row.id)
            return .handled
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Self.removeFromListTitle) { model.removeFromList(row) }
        .contextMenu {
            // The selection, when this row is one of several selected, as in Finder.
            Button { model.removeFromList(row) } label: { Self.removeFromListTitle }
        }
    }

    private var isSelected: Bool { model.selectedAppIDs.contains(row.id) }

    private static var removeFromListTitle: Text {
        Text("Remove from List", comment: "Settings → Sound Sources: item of an app's contextual menu that forgets it")
    }
}
