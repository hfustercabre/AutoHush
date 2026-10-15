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
    /// Where the entries are scrolled to: the newest, at first.
    @State private var position = ScrollPosition(edge: .bottom)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchField(text: $model.search)
                Picker(selection: $model.range) {
                    ForEach(LogsModel.Range.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Text("Time Range", comment: "The logs window: VoiceOver's name of the pop-up that chooses how far back the logs go (This Launch, Last 24 Hours)")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                Picker(selection: $model.levels) {
                    ForEach(LogsModel.Levels.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Text("Levels", comment: "The logs window: VoiceOver's name of the pop-up that chooses which entries show (All Levels, Problems Only)")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
            lines
            BottomBar(margin: HostedWindowController.margin) {
                Toggle(isOn: $model.followsNewEntries) { Text(verbatim: Self.followTitle) }
                    .toggleStyle(PillToggleStyle(width: 30, height: 18))
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

    /// The entries, newest at the bottom, following new ones while asked to.
    private var lines: some View {
        let shown = model.shown
        return ScrollView {
            Card {
                if shown.isEmpty {
                    Text(verbatim: emptyNote).foregroundStyle(.appSecondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { index, entry in
                            if index > 0 { CardDivider() }
                            LogRow(entry: entry)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .scrollPosition($position)
        // Opened at the newest entry; a few entries stay at the top.
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.top, for: .alignment)
        .onChange(of: shown.count) {
            if model.followsNewEntries { position.scrollTo(edge: .bottom) }
        }
        .onChange(of: model.followsNewEntries) { _, follows in
            if follows { position.scrollTo(edge: .bottom) }
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if entry.level.isProblem {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.appWarning)
                } else {
                    Image(systemName: entry.level == .notice ? "circle.fill" : "circle")
                        .font(.system(size: 6))
                        .foregroundStyle(.appSecondary)
                }
            }
            .frame(width: 14)
            .accessibilityHidden(true)
            Text(verbatim: Self.time(entry.date))
                .monospacedDigit()
                .foregroundStyle(.appSecondary)
            Text(verbatim: LogsModel.area(of: entry.category))
                .font(.appCaption)
                .foregroundStyle(.appSecondary)
                .frame(width: 70, alignment: .leading)
            Text(verbatim: entry.message)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: [entry.level.isProblem ? Self.problem : nil, Self.time(entry.date),
                                            LogsModel.area(of: entry.category), entry.message].compactMap { $0 }.joined(separator: ", ")))
    }

    /// Today's lines by their time; yesterday's with their day too.
    private static func time(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .standard)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute().second())
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
