import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AutoHushKit

/// Settings → Sound Sources: which apps pause the music, as a section of
/// macOS's grouped form, each with its switch as in the menu's "Playing
/// Now", in the order the user chose; a magnifier opens a search by name in
/// place of the heading. A click selects
/// an app, ⌘-click and ⇧-click several, as in macOS's lists, and Remove
/// (or Delete) takes them off the list (asking first when one is turned off, which then
/// pauses the music again). The page fills the window: the list scrolls
/// between the heading and the buttons.
struct SoundSourcesSettingsView: View {
    let model: SettingsModel

    /// The list's rows, order, search, selection and removals.
    private var list: AppListModel { model.appList }
    /// Opens Sort by's pop-up from the keys.
    @State private var sortPopUp = PopUpOpener()
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    var body: some View {
        page
        // Settings' window is kept when closed: a selection doesn't outlive it.
        .onDisappear { list.clearSelection() }
    }

    /// The heading, the list that scrolls, and the buttons.
    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The list as a section of macOS's grouped form, its sort and search over it.
            Form {
                Card(heading: AnyView(header)) {
                    if list.apps.isEmpty {
                        Text(verbatim: Self.emptyText)
                            .foregroundStyle(.appSecondary)
                    } else if list.shownApps.isEmpty, let search = list.search {
                        Text(verbatim: Self.noMatch(search))
                            .foregroundStyle(.appSecondary)
                    }
                    ForEach(Array(list.shownApps.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { CardDivider() }
                        SoundSourceRow(model: model, row: row)
                    }
                } footer: {
                    if let footer = Self.footer(listIsEmpty: list.apps.isEmpty) {
                        Text(verbatim: footer)
                            .captionStyle()
                    }
                }
                // Rows slide as the list changes, but with Reduce Motion on (A11, 2026-11-01).
                .animation(reducesMotion ? nil : .default, value: list.apps)
            }
            .formStyle(.grouped)
            .measuresHighlightPage() // Page Up and Page Down go about its height
            .environment(\.cardsAreFormSections, true)
            // Each button on one line, in every language: three of them leave
            // little room.
            BottomBar {
                Button { IgnoreAppsPicker.run(player: model.chosenPlayer) { model.settings.setIgnored($0, true) } } label: {
                    Text(verbatim: IgnoreAppsPicker.title(noneIgnored: model.state.ignoredApps.isEmpty))
                }
                    .buttonStyle(.chip)
                    .fixedSize()
                Button { list.removeSelected() } label: { Text(verbatim: PlayerAlerts.removeTitle) }
                    .buttonStyle(.chip)
                    .fixedSize()
                    .disabled(list.selectedApps.isEmpty)
                Spacer(minLength: 0)
                Button(role: .destructive) { confirmReset() } label: {
                    Text("Reset List…", comment: "Settings → Sound Sources: button that asks to forget every app in the list")
                }
                    .buttonStyle(.chip)
                    .fixedSize()
                    .disabled(list.apps.isEmpty)
            }
            // The arrow keys reach them after the list, however it's scrolled.
            .environment(\.highlightBand, .bottom)
        }
        // Asked as every removal is (`PlayerAlerts.confirm`): its button
        // blue, not red (the user, 2026-10-20), after this update.
        .onChange(of: list.appsAwaitingRemoval) { _, rows in
            guard !rows.isEmpty else { return }
            InfoAlert.whenNoneOpen { confirmRemoval(rows) }
        }
    }

    private func confirmReset() {
        let alert = PlayerAlerts.confirm(
            title: String(localized: "Reset the list of apps?", comment: "Settings → Sound Sources: title of the confirmation for Reset List"),
            message: String(localized: "All apps are removed; ignored ones will pause your player again.",
                            comment: "Settings → Sound Sources: what Reset List does, in its confirmation"),
            button: String(localized: "Reset List", comment: "Settings → Sound Sources: confirms forgetting every app in the list"))
        if InfoAlert.runInFront(alert) == .alertFirstButtonReturn { model.settings.forgetAll() }
    }

    private func confirmRemoval(_ rows: [AppListModel.Row]) {
        let alert = PlayerAlerts.confirm(title: Self.removalTitle(names: list.removalNames), message: Self.removalMessage(rows),
                                         button: PlayerAlerts.removeTitle)
        if InfoAlert.runInFront(alert) == .alertFirstButtonReturn { list.confirmRemoval() } else { list.cancelRemoval() }
    }

    /// The removal's confirmation's message: the ignored app by its name
    /// when only one of those asked about is (the full check, 2026-10-18),
    /// else "some of them".
    static func removalMessage(_ rows: [AppListModel.Row]) -> String {
        let off = rows.filter(\.isIgnored)
        guard off.count > 1 else {
            let name = (off.first ?? rows.first)?.source.name ?? ""
            return String(localized: "\(name) is ignored now. Removed from the list, it pauses your player again when it plays.",
                          comment: "Settings → Sound Sources: what removing an app that's ignored (its switch off) does, in its confirmation; %@ is the app")
        }
        return String(localized: "Some of them are ignored now. Removed from the list, they pause your player again when they play.",
                      comment: "Settings → Sound Sources: what removing several selected apps does when one of them at least is ignored (its switch off), in its confirmation")
    }

    /// The confirmation's title: the app's name for one, how many for several.
    static func removalTitle(names: [String]) -> String {
        names.count == 1
            ? String(localized: "Remove \(names[0]) from the list?",
                     comment: "Settings → Sound Sources: title of the confirmation for removing an app that's turned off; %@ is the app")
            : String(localized: "Remove \(names.count) apps from the list?",
                     comment: "Settings → Sound Sources: title of the confirmation for removing several selected apps, one of them at least turned off; %lld is how many (2 or more)")
    }

    /// Instead of the apps while the list is empty: what fills it, and the
    /// button that adds an app now, by its own title (T15b, the user's pick,
    /// 2026-11-02). An empty list has no ignored app: the button is Ignore an
    /// App….
    static var emptyText: String {
        let button = IgnoreAppsPicker.title(noneIgnored: true)
        return String(localized: "Apps appear here once they play. \(button) adds one now.",
                      comment: "Settings → Sound Sources, while the list is empty; %@ is the title of the button under the list, “Ignore an App…”, which opens a panel to pick apps to ignore")
    }

    /// Under the list, none while it's empty: there's nothing to select
    /// (T15b, the user's pick, 2026-11-02).
    static func footer(listIsEmpty: Bool) -> String? {
        listIsEmpty ? nil
            : String(localized: "Ignored apps don’t pause your player. Select apps to remove them.",
                     comment: "Settings → Sound Sources, under the list; “Ignored” as the apps whose switch is off; “Select” as in clicking apps in the list (⌘-click or ⇧-click selects several)")
    }

    /// Instead of the apps when the search finds none.
    private static func noMatch(_ search: String) -> String {
        String(localized: "No apps match “\(search)”.",
               comment: "Settings → Sound Sources, when the search finds nothing; %@ is what was typed")
    }

    /// The search, in the heading's place while it's open: its ✕ closes it.
    static func searchField(_ list: AppListModel) -> SearchField {
        // A closing field hands back its text as it loses focus: only an
        // open search takes it.
        SearchField(text: Binding(
            get: { list.search ?? "" },
            set: { text in if list.search != nil { list.search = text } }
        ), focusesOnAppear: true, results: SearchResults(count: list.shownApps.count, noMatch: noMatch(list.search ?? "")),
                    onClose: { list.search = nil })
    }

    /// The heading, or the search while it's open, then "Sort by" with the
    /// order's pop-up, an arrow that reverses it, and the magnifier.
    private var header: some View {
        let order = list.order
        return HStack(spacing: 6) {
            if list.search != nil {
                Self.searchField(list).padding(.trailing, 10)
            } else {
                SectionHeading(Text("Apps", comment: "Settings → Sound Sources: heading of the list of the apps heard playing, each switched to pause your player or be ignored"), isFirst: true)
                Spacer()
            }
            Self.sortByTitle
                .font(.appCaption)
                .foregroundStyle(.appSecondary)
                .fixedSize() // on one line, in every language
                .accessibilityHidden(true) // the pop-up says it, as its label
            Picker(selection: Binding(
                get: { order.criterion },
                set: { list.setOrder(AppListOrder(criterion: $0)) }
            )) {
                ForEach(AppListOrder.Criterion.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Self.sortByTitle
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .buttonStyle(.borderless)
            .fixedSize()
            .opened(by: sortPopUp)
            // ← and → choose the order, while the arrow keys' highlight is on
            // it; Return or Space shows the choices, as About's update pop-up
            // (`PopUpOpener`, 2026-10-27).
            .modifier(Highlightable(cornerRadius: 6, outset: 3, press: { sortPopUp.open() }, adjust: { step in
                if let criterion = AppListOrder.Criterion.allCases.stepping(from: list.order.criterion, by: step) {
                    list.setOrder(AppListOrder(criterion: criterion))
                }
            }, arrivalSpeech: PopUpOpener.arrivalSpeech(Self.sortByString) { list.order.criterion.title }))
            IconChipButton(
                symbol: order.isReversed ? "arrow.up" : "arrow.down",
                label: Text("Reverse order", comment: "Settings → Sound Sources: the arrow that reverses the apps' order"),
                help: Text(verbatim: String(localized: "\(order.directionTitle). Click to reverse the order.",
                                            comment: "Settings → Sound Sources, the arrow beside Sort by; %@ is the order now, e.g. “Newest first”"))
            ) {
                list.setOrder(AppListOrder(criterion: order.criterion, isReversed: !order.isReversed))
            }
            .accessibilityValue(Text(verbatim: order.directionTitle))
            if list.search == nil {
                IconChipButton(symbol: "magnifyingglass",
                               label: Text("Search by name", comment: "The magnifier that opens a search")) {
                    list.search = ""
                }
                .disabled(list.apps.isEmpty)
            }
        }
    }

    /// Before the order's pop-up, and its name for VoiceOver.
    private static var sortByTitle: Text {
        Text(verbatim: sortByString)
    }

    private static var sortByString: String {
        String(localized: "Sort by", comment: "Settings → Sound Sources, before the pop-up that orders the apps")
    }
}

extension AppListOrder.Criterion {
    /// Its name in Settings → Sound Sources' Sort by pop-up.
    var title: String {
        switch self {
        case .lastPlayed: String(localized: "Last Played", comment: "Settings → Sound Sources, Sort by: the app that played most recently first")
        case .name:       String(localized: "Name", comment: "Settings → Sound Sources, Sort by: alphabetically")
        case .state:      String(localized: "Status", comment: "Settings → Sound Sources, Sort by: by each app's switch, apps that pause your player first, then the ignored ones")
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
/// the music, and its switch; selected, on the accent color with its text
/// white, as macOS's lists (A1a, the user's pick, 2026-11-01: the faint
/// selection looked like the pointer's highlight). A click selects the row anywhere but on the
/// switch, which keeps its own clicks, ⌘ and ⇧ as in macOS's lists; from
/// the keyboard, Return switches the highlighted app on or off and Space
/// adds its row to the selection or takes it out, so several can be
/// removed too (the user, 2026-11-03). The arrow keys (Tab too) and the
/// pointer highlight it, as Settings' other rows. VoiceOver hears it as one,
/// as a `SwitchRow`: the switch, named by the app, its words its hint (VO8,
/// the a11y audit, 2026-11-06).
private struct SoundSourceRow: View {
    let model: SettingsModel
    let row: AppListModel.Row
    @FocusState private var rowFocused: Bool
    @FocusState private var switchFocused: Bool
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?
    @Environment(\.voiceOver) private var voiceOver

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: AppIcon.image(for: row.source, players: model.playerOptions, size: 24))
                    .resizable()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                RowTitle(
                    Text(verbatim: row.source.name),
                    subtitle: Text(verbatim: subtitle),
                    isOnSelection: isSelected
                )
                .accessibilityHidden(true) // the switch says it
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                let keys = NSEvent.modifierFlags
                list.click(on: row.id, command: keys.contains(.command), shift: keys.contains(.shift))
            }
            Toggle(isOn: isOn) {
                Text(verbatim: row.source.name)
            }
            .toggleStyle(PillToggleStyle())
            .focused($switchFocused)
            .focusEffectDisabled(keyboard != nil)
            .accessibilityHint(Text(verbatim: subtitle))
            // A white ground while it's on, so its accent color shows on the
            // selection; off, macOS's own switch on the selection, whose
            // track shows there (D1b, the a11y audit's D1, the user's pick,
            // 2026-11-06: on white, an off switch vanished in dark mode).
            .background { if isSelected, isOn.wrappedValue { Capsule().fill(.onSelection).padding(-2) } }
        }
        .background {
            if isSelected { SelectionFill().padding(.horizontal, -6).padding(.vertical, -4) }
        }
        .contentShape(Rectangle())
        .focusable(interactions: .activate) // as a button: Tab, not a click, gives it focus
        .focused($rowFocused)
        .focusEffectDisabled(keyboard != nil) // the row's tint shows it
        // The arrow keys and the pointer highlight it, its tint as far out as
        // the selection's; Return switches the app on or off, Space adds it
        // to the selection or takes it out.
        .highlightableRow(isFocused: rowFocused || switchFocused, cornerRadius: 6, vertical: 4,
                          press: switchFromKeys,
                          select: { list.toggleSelection(of: row.id) })
        .onKeyPress(.space) {
            list.toggleSelection(of: row.id)
            return .handled
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Self.removeFromListTitle) { list.removeFromList(row) }
        .contextMenu {
            // The selection, when this row is one of several selected, as in Finder.
            Button { list.removeFromList(row) } label: { Self.removeFromListTitle }
        }
    }

    private var list: AppListModel { model.appList }
    private var isSelected: Bool { list.selectedAppIDs.contains(row.id) }
    /// Under its name: whether it pauses the player, mutes it or is ignored.
    private var subtitle: String { SourceText.subtitle(isIgnored: row.isIgnored, mutes: model.playerMutesNow) }
    /// The switch: on while the app pauses the player, off while it's ignored.
    private var isOn: Binding<Bool> {
        Binding(get: { !row.isIgnored }, set: { model.settings.setIgnored(row.source, !$0) })
    }

    /// Return on the row: the app switched on or off, and VoiceOver told
    /// what it does now, which it doesn't say when the switch changes from
    /// the row (the a11y round 2's leftovers, 2026-11-06).
    private func switchFromKeys() {
        let ignores = !row.isIgnored
        model.settings.setIgnored(row.source, ignores)
        guard voiceOver.isOn() else { return }
        postStepAnnouncement(row.source.name + ", " + SourceText.subtitle(isIgnored: ignores, mutes: model.playerMutesNow))
    }

    private static var removeFromListTitle: Text {
        Text("Remove from List", comment: "Settings → Sound Sources: item of an app's contextual menu that forgets it")
    }
}

/// A selected Sound Sources row's ground: macOS's selection color; where
/// the keys' highlight is, outlined inside in white, as the highlight's
/// accent outline, behind it, doesn't show (A1a, A2a).
private struct SelectionFill: View {
    @Environment(\.keyHighlightByKeys) private var byKeys

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        shape
            .fill(.listSelectionFill)
            .overlay { if byKeys { shape.strokeBorder(.onSelection, lineWidth: 2) } }
    }
}
