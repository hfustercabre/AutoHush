import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AutoHushKit

/// The logs window's content: a search, how far back and which levels,
/// AutoHush's lines in a card, oldest first, then following new lines, and
/// Copy Logs and Save… at the foot. The lines are in English, as logged.
/// The keys' highlight (`LogsWindowController.keys`) goes through its
/// controls and its entries, one stop, as in Settings (R6, the user,
/// 2026-11-10: reach every control).
struct LogsView: View {
    @Bindable var model: LogsModel
    /// ↑ (-1) or ↓ (1) on the entries while the keys' highlight is on them:
    /// they scroll; `false` at that end (`LogsWindowController`).
    var scrollEntries: @MainActor (Int) -> Bool = { _ in false }
    /// The end of the entries, scrolled to on macOS 14 (`FollowsNewest`).
    static let bottom = "bottom"
    /// Open the pop-ups from the keys.
    @State private var rangePopUp = PopUpOpener()
    @State private var levelsPopUp = PopUpOpener()
    @FocusState private var followFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchField(text: $model.search, results: SearchResults(count: model.shown.count, noMatch: emptyNote))
                Picker(selection: $model.range) {
                    ForEach(LogsModel.Range.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Text(verbatim: Self.rangeLabel)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .fixedSize()
                .opened(by: rangePopUp)
                // ← and → choose, Return or Space shows the choices, as Settings' pop-ups.
                .modifier(Highlightable(cornerRadius: 6, outset: 3, press: { rangePopUp.open() }, adjust: { step in
                    if let range = LogsModel.Range.allCases.stepping(from: model.range, by: step) { model.range = range }
                }, arrivalSpeech: PopUpOpener.arrivalSpeech(Self.rangeLabel) { model.range.title }))
                Picker(selection: $model.levels) {
                    ForEach(LogsModel.Levels.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Text(verbatim: Self.levelsLabel)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .fixedSize()
                .opened(by: levelsPopUp)
                .modifier(Highlightable(cornerRadius: 6, outset: 3, press: { levelsPopUp.open() }, adjust: { step in
                    if let levels = LogsModel.Levels.allCases.stepping(from: model.levels, by: step) { model.levels = levels }
                }, arrivalSpeech: PopUpOpener.arrivalSpeech(Self.levelsLabel) { model.levels.title }))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
            if !model.shown.isEmpty { columnTitles }
            lines
            BottomBar {
                // The switch and its title, one stop for the keys, as Settings' switch rows.
                HStack {
                    Toggle(isOn: $model.followsNewEntries) { Text(verbatim: Self.followTitle) }
                        .toggleStyle(PillToggleStyle())
                        .focused($followFocused)
                        .focusEffectDisabled() // the row's tint shows it
                    Text(verbatim: Self.followTitle)
                        .font(.appCallout)
                        .foregroundStyle(.appSecondary)
                        .accessibilityHidden(true) // the switch says it
                }
                .highlightableRow(isFocused: followFocused, press: { model.followsNewEntries.toggle() })
                Spacer()
                Button(action: save) {
                    Text("Save…", comment: "The logs window: button that saves the entries shown to a text file")
                }
                .buttonStyle(.chip)
                .disabled(model.shown.isEmpty)
                // "Copied" for a moment after a click, as Diagnostics' Copy Report.
                CopyButton(title: Text(verbatim: Self.copyTitle)) { model.text }
                    .disabled(model.shown.isEmpty)
            }
        }
        .font(.appBody)
        .frame(minWidth: LogsWindowController.minimumSize.width, minHeight: LogsWindowController.minimumSize.height)
    }

    /// What each column shows, above the card, in line with its rows; it
    /// stays while the entries scroll.
    private var columnTitles: some View {
        HStack(alignment: .firstTextBaseline, spacing: LogColumns.spacing) {
            Text(LogColumns.levelTitle).frame(width: LogColumns.shared.level)
            Text(LogColumns.timeTitle).frame(width: LogColumns.shared.time, alignment: .leading)
            Text(LogColumns.areaTitle).frame(width: LogColumns.shared.area, alignment: .leading)
            Text(LogColumns.messageTitle)
            Spacer(minLength: 0)
        }
        .font(.appCaption.weight(.semibold))
        .foregroundStyle(.appSecondary)
        .lineLimit(1)
        .padding(.horizontal, 20 + LogColumns.cardInset)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }

    /// The entries, newest at the bottom, following new ones while asked to.
    private var lines: some View {
        let shown = model.shown
        return ScrollView {
            VStack(spacing: 0) {
                Card {
                    if shown.isEmpty && model.isLoading {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    } else if shown.isEmpty {
                        Text(verbatim: emptyNote).foregroundStyle(.appSecondary)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            // By time: as the oldest go and new ones come, the
                            // others keep their rows.
                            ForEach(shown.keyed(by: \.date)) { keyed in
                                if keyed.offset > 0 { CardDivider() }
                                LogRow(entry: keyed.element)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                // Below the card and its margin, so the newest entry shows whole.
                Color.clear.frame(height: 0).id(Self.bottom)
            }
        }
        .modifier(FollowsNewest(newest: FollowsNewest.Newest(shown), follows: model.followsNewEntries))
        // One stop for the keys: ↑ and ↓ scroll them, then go on at their ends.
        .overlay { EntriesRing() }
        .modifier(Highlightable(lightsItself: true, scroll: scrollEntries))
    }

    /// The entries' outline while the keys are on them: over them, as a
    /// tint behind would be hidden by the card (a filled control's ring, P1).
    private struct EntriesRing: View {
        @Environment(\.showsKeyHighlight) private var isLit
        @Environment(\.keyHighlightByKeys) private var byKeys

        var body: some View {
            HighlightTint(isFocused: isLit, byKeys: byKeys, cornerRadius: 10, ring: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
        }
    }

    /// Opened at the newest entry, and following new ones while asked to:
    /// on macOS 15 by its scroll position (a few entries stay at the top),
    /// on macOS 14 by scrolling to the end's marker (`LogsView.bottom`).
    struct FollowsNewest: ViewModifier {
        /// What a new entry changes: how many show and the last one, as one
        /// coming while the oldest goes (24 hours on) leaves the count as it
        /// was (app-views-1, the bug hunt, 2026-11-10).
        struct Newest: Equatable {
            let count: Int
            let last: LogEntry?

            init(_ shown: [LogEntry]) {
                count = shown.count
                last = shown.last
            }
        }

        let newest: Newest
        let follows: Bool

        func body(content: Content) -> some View {
            if #available(macOS 15, *) {
                content.modifier(FollowsNewestByPosition(newest: newest, follows: follows))
            } else {
                ScrollViewReader { proxy in
                    content
                        .defaultScrollAnchor(.bottom)
                        .onChange(of: newest) { if follows { proxy.scrollTo(LogsView.bottom, anchor: .bottom) } }
                        .onChange(of: follows) { _, follows in if follows { proxy.scrollTo(LogsView.bottom, anchor: .bottom) } }
                }
            }
        }
    }

    @available(macOS 15, *)
    private struct FollowsNewestByPosition: ViewModifier {
        let newest: FollowsNewest.Newest
        let follows: Bool
        /// Where the entries are scrolled to: the newest, at first.
        @State private var position = ScrollPosition(edge: .bottom)

        func body(content: Content) -> some View {
            content
                .scrollPosition($position)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.top, for: .alignment)
                .onChange(of: newest) { if follows { position.scrollTo(edge: .bottom) } }
                .onChange(of: follows) { _, follows in if follows { position.scrollTo(edge: .bottom) } }
        }
    }

    private var emptyNote: String {
        let query = model.search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            return String(localized: "No entries match “\(query)”.",
                          comment: "The logs window, when the search finds nothing; %@ is what was typed")
        }
        if model.levels == .problems {
            return String(localized: "No problems were logged.", comment: "The logs window, showing problems only, when there are none")
        }
        return String(localized: "Nothing was logged yet.", comment: "The logs window, while AutoHush has logged nothing in the time shown")
    }

    private static var rangeLabel: String {
        String(localized: "Time range", comment: "The logs window: VoiceOver's name of the pop-up that chooses how far back the logs go (This Launch, Last 24 Hours)")
    }

    private static var levelsLabel: String {
        String(localized: "Levels", comment: "The logs window: VoiceOver's name of the pop-up that chooses which entries show (All Levels, Problems Only)")
    }

    private static var followTitle: String {
        String(localized: "Follow new entries", comment: "The logs window: switch at its foot; on, the list scrolls to each new entry as AutoHush logs it")
    }

    private static var copyTitle: String {
        String(localized: "Copy Logs", comment: "The logs window: button that puts the entries shown on the clipboard")
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = LogsWindowController.title + ".txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            InfoAlert.show(String(localized: "Couldn’t Save the Logs", comment: "Alert title, when the logs window's Save… failed"),
                           error.localizedDescription)
        }
    }
}

extension LogsModel.Range {
    var title: String {
        switch self {
        case .thisLaunch:
            String(localized: "This Launch", comment: "The logs window's time pop-up: the entries since AutoHush last opened (at most its last 24 hours)")
        case .last24Hours:
            String(localized: "Last 24 Hours", comment: "The logs window's time pop-up: the entries of the last 24 hours, earlier launches included")
        }
    }
}

extension LogsModel.Levels {
    var title: String {
        switch self {
        case .all:
            String(localized: "All Levels", comment: "The logs window's level pop-up: every entry")
        case .problems:
            String(localized: "Problems Only", comment: "The logs window's level pop-up: only the entries that logged an error")
        }
    }
}
