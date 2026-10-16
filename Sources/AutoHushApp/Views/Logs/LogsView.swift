import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AutoHushKit

/// The logs window's content: a search, how far back and which levels,
/// AutoHush's lines in a card, oldest first, then following new lines, and
/// Copy Logs and Save… at the foot. The lines are in English, as logged.
struct LogsView: View {
    @Bindable var model: LogsModel
    @State private var copied = false
    /// The end of the entries, scrolled to on macOS 14 (`FollowsNewest`).
    static let bottom = "bottom"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchField(text: $model.search)
                Picker(selection: $model.range) {
                    ForEach(LogsModel.Range.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Text("Time range", comment: "The logs window: VoiceOver's name of the pop-up that chooses how far back the logs go (This Launch, Last 24 Hours)")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .fixedSize()
                Picker(selection: $model.levels) {
                    ForEach(LogsModel.Levels.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Text("Levels", comment: "The logs window: VoiceOver's name of the pop-up that chooses which entries show (All Levels, Problems Only)")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
            if !model.shown.isEmpty { columnTitles }
            lines
            BottomBar(margin: HostedWindowController.margin) {
                Toggle(isOn: $model.followsNewEntries) { Text(verbatim: Self.followTitle) }
                    .toggleStyle(PillToggleStyle())
                Text(verbatim: Self.followTitle)
                    .font(.appCallout)
                    .foregroundStyle(.appSecondary)
                    .accessibilityHidden(true) // the switch says it
                Spacer()
                Button(action: save) {
                    Text("Save…", comment: "The logs window: button that saves the entries shown to a text file")
                }
                .buttonStyle(.chip)
                .disabled(model.shown.isEmpty)
                Button(action: copy) {
                    Text(verbatim: copied ? DiagnosticsSettingsView.copiedText : Self.copyTitle)
                }
                .buttonStyle(.chip)
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
            Card {
                if shown.isEmpty && model.isLoading {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                } else if shown.isEmpty {
                    Text(verbatim: emptyNote).foregroundStyle(.appSecondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { index, entry in
                            if index > 0 { CardDivider() }
                            LogRow(entry: entry)
                        }
                        Color.clear.frame(height: 0).id(Self.bottom)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .modifier(FollowsNewest(count: shown.count, follows: model.followsNewEntries))
    }

    /// Opened at the newest entry, and following new ones while asked to:
    /// on macOS 15 by its scroll position (a few entries stay at the top),
    /// on macOS 14 by scrolling to the end's marker (`LogsView.bottom`).
    private struct FollowsNewest: ViewModifier {
        let count: Int
        let follows: Bool

        func body(content: Content) -> some View {
            if #available(macOS 15, *) {
                content.modifier(FollowsNewestByPosition(count: count, follows: follows))
            } else {
                ScrollViewReader { proxy in
                    content
                        .defaultScrollAnchor(.bottom)
                        .onChange(of: count) { if follows { proxy.scrollTo(LogsView.bottom, anchor: .bottom) } }
                        .onChange(of: follows) { _, follows in if follows { proxy.scrollTo(LogsView.bottom, anchor: .bottom) } }
                }
            }
        }
    }

    @available(macOS 15, *)
    private struct FollowsNewestByPosition: ViewModifier {
        let count: Int
        let follows: Bool
        /// Where the entries are scrolled to: the newest, at first.
        @State private var position = ScrollPosition(edge: .bottom)

        func body(content: Content) -> some View {
            content
                .scrollPosition($position)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.top, for: .alignment)
                .onChange(of: count) { if follows { position.scrollTo(edge: .bottom) } }
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

    private static var followTitle: String {
        String(localized: "Follow new entries", comment: "The logs window: switch at its foot; on, the list scrolls to each new entry as AutoHush logs it")
    }

    private static var copyTitle: String {
        String(localized: "Copy Logs", comment: "The logs window: button that puts the entries shown on the clipboard")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.text, forType: .string)
        copied = true
        AccessibilityNotification.Announcement(DiagnosticsSettingsView.copiedText).post()
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
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

/// One line of the log: whether it's a problem, when, which part of
/// AutoHush, and what it says (selectable).
private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LogColumns.spacing) {
            Group {
                if entry.level.isProblem {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.appWarning)
                } else {
                    Image(systemName: entry.level == .notice ? "circle.fill" : "circle")
                        .font(.system(size: 6))
                        .foregroundStyle(.appSecondary)
                }
            }
            .frame(width: LogColumns.shared.level)
            .accessibilityHidden(true)
            Text(verbatim: Self.time(entry.date))
                .monospacedDigit()
                .foregroundStyle(.appSecondary)
                .frame(width: LogColumns.shared.time, alignment: .leading)
            Text(verbatim: LogsModel.area(of: entry.category))
                .font(.appCaption)
                .foregroundStyle(.appSecondary)
                .frame(width: LogColumns.shared.area, alignment: .leading)
            Text(verbatim: entry.message)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: [entry.level.isProblem ? Self.problem : nil, Self.time(entry.date),
                                            LogsModel.area(of: entry.category), entry.message].compactMap { $0 }.joined(separator: ", ")))
    }

    private static func time(_ date: Date) -> String {
        LogsModel.timestamp(of: date)
    }

    private static var problem: String {
        String(localized: "Problem", comment: "VoiceOver, the logs window: before an entry that logged an error")
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

/// The logs window's columns: the level's mark, when, the area and the
/// message. Each is as wide as its title, in the user's language, or its
/// widest entry, so the titles above the card line up with the rows.
@MainActor
private struct LogColumns {
    static let spacing: CGFloat = 12
    /// The card's padding, which the titles are in line with.
    static var cardInset: CGFloat {
        if #available(macOS 26, *) { 14 } else { 12 }
    }
    static let shared = LogColumns()

    let level: CGFloat
    let time: CGFloat
    let area: CGFloat

    private init() {
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        let title = NSFont.systemFont(ofSize: 11, weight: .semibold)
        // The longest time: a two-digit day and hour, and the Mac's offset
        // from UTC in summer and in winter.
        let now = Date()
        let times = [now, now.addingTimeInterval(182 * 24 * 60 * 60)].map {
            "00/00/0000 00:00:00 " + LogsModel.utcOffset(seconds: TimeZone.current.secondsFromGMT(for: $0))
        }
        level = max(14, width(Self.levelTitle, title))
        time = max(times.map { width($0, .monospacedDigitSystemFont(ofSize: 14, weight: .regular)) }.max() ?? 0,
                   width(Self.timeTitle, title))
        area = max(LogsModel.areas.map { width($0, .systemFont(ofSize: 11)) }.max() ?? 0, width(Self.areaTitle, title))
    }

    static var levelTitle: String {
        String(localized: "Level", comment: "The logs window: title of the column that marks each entry's level (a problem, a notice, information)")
    }

    static var timeTitle: String {
        String(localized: "Time", comment: "The logs window: title of the column with when each entry was logged (its date, time and offset from UTC)")
    }

    static var areaTitle: String {
        String(localized: "Area", comment: "The logs window: title of the column with the part of AutoHush that logged each entry (Player, Detection, Updates…)")
    }

    static var messageTitle: String {
        String(localized: "Message", comment: "The logs window: title of the column with what each entry says")
    }
}
