import SwiftUI
import AutoHushKit

/// "Turn off for" and a button per duration: one click turns auto-pause off
/// for that long.
struct SnoozeBarView: View {
    let model: StatusMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(Text("Turn off for", comment: "Menu: above the buttons that turn auto-pause off for a while"))
            HStack(spacing: 6) {
                ForEach(AutoPauseSnooze.allCases, id: \.self) { snooze in
                    Button { model.perform(.snooze(snooze)) } label: {
                        Text(verbatim: snooze.shortTitle)
                            .font(.callout)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(ChipButtonStyle(filled: true))
                    .accessibilityLabel(snooze.title)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: menuContentWidth)
    }
}

extension AutoPauseSnooze {
    /// The duration on its button, e.g. "15 min" or "1 hr", in the user's language.
    var shortTitle: String {
        Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
