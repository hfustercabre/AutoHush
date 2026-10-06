import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AutoHushKit

/// Settings → Apps: which apps pause the music, in a card like the menu's
/// "Playing Now", each with its switch, in the order the user chose; a
/// magnifier opens a search by name in place of the heading. The tab grows
/// with the list up to Advanced's height; a longer list scrolls under the
/// heading.
struct AppsSettingsView: View {
    let model: SettingsModel
    @State private var confirmingReset = false
    /// The heights of the list (with its note) and of the parts above and
    /// below it, which don't scroll.
    @State private var listHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var barHeight: CGFloat = 0
    /// The height when the search opened, kept while it's open so the window
    /// doesn't shrink as the list narrows down.
    @State private var heightWhileSearching: CGFloat?

    /// The tab's height with a short list.
    static let minimumHeight: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { headerHeight = $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Card {
                        if model.apps.isEmpty {
                            Text("Apps appear here once they have played audio.")
                                .foregroundStyle(.appSecondary)
                        } else if model.shownApps.isEmpty, let search = model.appSearch {
                            Text(verbatim: String(localized: "No apps match “\(search)”.",
                                                  comment: "Settings → Apps, when the search finds nothing; %@ is what was typed"))
                                .foregroundStyle(.appSecondary)
                        }
                        ForEach(Array(model.shownApps.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { CardDivider() }
                            appRow(row)
                        }
                    }
                    .animation(.default, value: model.apps)
                    Text("Turn an app off to keep your music playing while it makes sound. Right-click an app to remove it from the list.")
                        .captionStyle()
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { listHeight = $0 }
            }
            BottomBar(showsDivider: listScrolls) {
                Button("Ignore Another App…") { chooseAppToIgnore() }
                    .buttonStyle(.chip)
                Spacer()
                Button("Reset List…", role: .destructive) { confirmingReset = true }
                    .buttonStyle(.chip)
                    .disabled(model.apps.isEmpty)
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { barHeight = $0 }
        }
        .confirmationDialog("Reset the list of apps?", isPresented: $confirmingReset) {
            Button("Reset List", role: .destructive) { model.forgetAllApps() }
        } message: {
            Text("Every app is removed, and apps you turned off will pause your music again. Apps reappear as they play audio.")
        }
        .frame(width: 480, height: heightWhileSearching ?? height)
        .onChange(of: model.appSearch != nil) { _, searching in
            heightWhileSearching = searching ? height : nil
        }
    }

    /// The list is longer than the room it has, so it scrolls under the
    /// buttons.
    private var listScrolls: Bool {
        headerHeight + listHeight + barHeight > (heightWhileSearching ?? height) + 1
    }

    /// As tall as the whole list, at least `minimumHeight` and at most
    /// Advanced's height.
    private var height: CGFloat {
        let whole = headerHeight + listHeight + barHeight
        return min(max(whole, Self.minimumHeight), max(model.appsMaximumHeight, Self.minimumHeight))
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
                SectionHeading(Text("Pauses Music"), isFirst: true)
                Spacer()
            }
            Text("Sort by", comment: "Settings → Apps, before the pop-up that orders the apps")
                .font(.appCaption)
                .foregroundStyle(.appSecondary)
                .fixedSize() // on one line, in every language
            Picker(selection: Binding(
                get: { order.criterion },
                set: { model.setAppListOrder(AppListOrder(criterion: $0)) }
            )) {
                ForEach(AppListOrder.Criterion.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Text("Sort by", comment: "Settings → Apps, before the pop-up that orders the apps")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .buttonStyle(.borderless)
            .fixedSize()
            IconChipButton(
                symbol: order.isReversed ? "arrow.up" : "arrow.down",
                label: Text("Reverse order", comment: "Settings → Apps: the arrow that reverses the apps' order"),
                help: Text(verbatim: String(localized: "\(order.directionTitle). Click to reverse the order.",
                                            comment: "Settings → Apps, the arrow beside Sort by; %@ is the order now, e.g. “Newest first”"))
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

    /// The app's icon and name, whether it pauses the music, and its switch.
    private func appRow(_ row: SettingsModel.AppRow) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIcon.image(for: row.source, size: 24))
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            RowTitle(
                Text(verbatim: row.source.name),
                subtitle: row.isIgnored ? Text("Ignored — music keeps playing") : Text("Pauses your music")
            )
            Spacer(minLength: 8)
            Toggle(isOn: Binding(
                get: { !row.isIgnored },
                set: { model.setPausesMusic($0, for: row.source) }
            )) {
                Text(verbatim: row.source.name)
            }
            .toggleStyle(PillToggleStyle(width: 30, height: 18))
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove from List") { model.forget(row.source) }
        }
    }

    private func chooseAppToIgnore() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose an App to Ignore", comment: "Title of the panel that picks an app")
        panel.prompt = String(localized: "Ignore", comment: "Button of the panel that picks an app to ignore")
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK,
              let url = panel.url,
              let source = ProcessAudioSourceIdentifier.source(forBundleAt: url)
        else { return }
        model.setPausesMusic(false, for: source)
    }
}

extension AppListOrder.Criterion {
    /// Its name in Settings → Apps' Sort by pop-up.
    var title: String {
        switch self {
        case .lastPlayed: String(localized: "Last Played", comment: "Settings → Apps, Sort by: the app that played most recently first")
        case .name:       String(localized: "Name", comment: "Settings → Apps, Sort by: alphabetically")
        case .state:      String(localized: "On/Off", comment: "Settings → Apps, Sort by: apps that pause the music first, then the ignored ones")
        }
    }
}

extension AppListOrder {
    /// Which way round it goes, in its criterion's words, e.g. "Newest first".
    var directionTitle: String {
        switch (criterion, isReversed) {
        case (.lastPlayed, false): String(localized: "Newest first", comment: "Settings → Apps: the order, the app that played last first")
        case (.lastPlayed, true):  String(localized: "Oldest first", comment: "Settings → Apps: the order, the app that played longest ago first")
        case (.name, false):       String(localized: "A to Z", comment: "Settings → Apps: the order, alphabetical")
        case (.name, true):        String(localized: "Z to A", comment: "Settings → Apps: the order, reverse alphabetical")
        case (.state, false):      String(localized: "Apps that pause the music first", comment: "Settings → Apps: the order, switched-on apps first")
        case (.state, true):       String(localized: "Ignored apps first", comment: "Settings → Apps: the order, switched-off apps first")
        }
    }
}
