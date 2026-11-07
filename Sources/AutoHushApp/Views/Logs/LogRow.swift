import SwiftUI
import AutoHushKit

/// One line of the log: whether it's a problem, when, which part of
/// AutoHush, and what it says (selectable).
struct LogRow: View {
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
