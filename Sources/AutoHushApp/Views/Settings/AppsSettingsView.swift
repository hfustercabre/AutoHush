import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AutoHushKit

/// Settings → Sound Sources: which apps pause the music, in a card like the menu's
/// "Playing Now", each with its switch, in the order the user chose; a
/// magnifier opens a search by name in place of the heading. A click selects
/// an app, which Remove takes off the list (asking first for one that's
/// turned off, which then pauses the music again). The page fills the
/// window: the list scrolls between the heading and the buttons.
struct AppsSettingsView: View {
    let model: SettingsModel
    @State private var confirmingReset = false
    /// The height of the list (with its note), and of the room it has.

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
                        appRow(row)
                    }
                } footer: {
                    Text("Turn an app off to keep your player playing while it makes sound. Select an app to remove it from the list.",
                         comment: "Settings → Sound Sources, under the list; “Select” as in clicking an app in the list")
                        .captionStyle()
                }
                .animation(.default, value: model.apps)
            }
            .formStyle(.grouped)
            .environment(\.cardsAreFormSections, true)
            // Each button on one line, in every language: three of them leave
            // little room.
            BottomBar {
                Button { chooseAppToIgnore() } label: {
                    Text("Ignore Another App…", comment: "Settings → Sound Sources: button that opens a panel to pick an app that never pauses your player")
                }
                    .buttonStyle(.chip)
                    .fixedSize()
                Button { if let selected = model.selectedApp { model.remove(selected) } } label: { Text(verbatim: Self.removeTitle) }
                    .buttonStyle(.chip)
                    .fixedSize()
                    .disabled(model.selectedApp == nil)
                Spacer(minLength: 0)
                Button(role: .destructive) { confirmingReset = true } label: {
                    Text("Reset List…", comment: "Settings → Sound Sources: button that asks to forget every app in the list")
                }
                    .buttonStyle(.chip)
                    .fixedSize()
                    .disabled(model.apps.isEmpty)
            }
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
        .confirmationDialog(Text(verbatim: String(localized: "Remove \(model.removalName) from the list?",
                                                  comment: "Settings → Sound Sources: title of the confirmation for removing an app that's turned off; %@ is the app")),
                            isPresented: Binding(get: { model.appAwaitingRemoval != nil }, set: { if !$0 { model.cancelRemoval() } }),
                            presenting: model.appAwaitingRemoval) { _ in
            Button(role: .destructive) { model.confirmRemoval() } label: { Text(verbatim: Self.removeTitle) }
        } message: { row in
            Text(verbatim: String(localized: "\(row.source.name) is turned off now. Removed from the list, it pauses your player again when it plays.",
                                  comment: "Settings → Sound Sources: what removing an app that's turned off does, in its confirmation; %@ is the app"))
        }
    }

    private static var removeTitle: String {
        String(localized: "Remove", comment: "A button that removes: under Settings → Sound Sources' list (the selected app), in its confirmation for an app that's turned off, and in the alert before an app added with Add an App is removed")
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
            Text("Sort by", comment: "Settings → Sound Sources, before the pop-up that orders the apps")
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
                Text("Sort by", comment: "Settings → Sound Sources, before the pop-up that orders the apps")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .buttonStyle(.borderless)
            .fixedSize()
            // ← and → choose the order, while the arrow keys' highlight is on it.
            .modifier(Highlightable(cornerRadius: 6, outset: 3, adjust: { step in
                let all = AppListOrder.Criterion.allCases
                guard let index = all.firstIndex(of: order.criterion) else { return }
                model.setAppListOrder(AppListOrder(criterion: all[min(max(index + step, 0), all.count - 1)]))
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

    private func appRow(_ row: SettingsModel.AppRow) -> some View {
        SoundSourceRow(model: model, row: row)
    }

    private func chooseAppToIgnore() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose an App to Ignore", comment: "Title of the panel that picks an app")
        panel.prompt = String(localized: "Ignore", comment: "Button of the panel that picks an app to ignore")
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let source = ProcessAudioSourceIdentifier.source(forBundleAt: url) else {
            let alert = Self.unidentifiedAppAlert(url: url)
            InfoAlert.show(alert.title, alert.message)
            return
        }
        model.settings.setIgnored(source, true)
    }

    /// The app chosen to ignore has no bundle identifier, which is how
    /// AutoHush tells apps' sound apart: it can't be ignored.
    static func unidentifiedAppAlert(url: URL) -> (title: String, message: String) {
        let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        return (String(localized: "Couldn’t Ignore \(name)",
                       comment: "Settings → Sound Sources: title of the alert after Ignore Another App… when the chosen app can't be ignored; %@ is the app's name"),
                String(localized: "\(name) doesn’t identify itself as Mac apps do, so AutoHush can’t tell when it plays.",
                       comment: "Settings → Sound Sources: the alert after Ignore Another App…, when the chosen app has no bundle identifier (the ID a Mac app has, which AutoHush tells apps' sound apart by); %@ is the app's name"))
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
/// switch, which keeps its own clicks; from the keyboard, Space selects the
/// row in focus (Tab reaches it with keyboard navigation on), so Remove is
/// reachable too. The arrow keys and the pointer highlight it, as Settings'
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
                    subtitle: row.isIgnored ? Text("Ignored — your player keeps playing", comment: "The menu's Playing Now and Settings → Sound Sources: under an app that is ignored, so your player keeps playing while it plays")
                        : Text(verbatim: PlayerOption.interruptsLabel(
                            mutes: model.playerOptions.first { $0.bundleID == model.chosenPlayerID }?.pausesByMuting == true))
                )
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.toggleSelection(of: row.id) }
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
            if row.id == model.selectedAppID {
                RoundedRectangle(cornerRadius: 6).fill(.selectedRowFill).padding(.horizontal, -6).padding(.vertical, -4)
            }
        }
        .contentShape(Rectangle())
        .focusable(interactions: .activate) // as a button: Tab, not a click, gives it focus
        .focused($rowFocused)
        .focusEffectDisabled(keyboard != nil) // the row's tint shows it
        // The arrow keys and the pointer highlight it; Return or Space selects it.
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .modifier(Highlightable(isFocused: rowFocused || switchFocused, cornerRadius: 6,
                                press: { model.toggleSelection(of: row.id) }))
        .padding(.horizontal, -6)
        .padding(.vertical, -4)
        .onKeyPress(.space) {
            model.toggleSelection(of: row.id)
            return .handled
        }
        .accessibilityAddTraits(row.id == model.selectedAppID ? .isSelected : [])
        .accessibilityAction(named: Text("Remove from List", comment: "Settings → Sound Sources: item of an app's contextual menu that forgets it")) { model.remove(row) }
        .contextMenu {
            Button { model.remove(row) } label: {
                Text("Remove from List", comment: "Settings → Sound Sources: item of an app's contextual menu that forgets it")
            }
        }
    }
}
