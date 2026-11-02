import SwiftUI
import AutoHushKit

/// "Turn off for" and a button per duration: one click turns auto-pause off
/// for that long. While one runs, "Turned off for", with that duration
/// selected and the time left; another click starts the one clicked.
struct SnoozeBarView: View {
    let model: StatusMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: MenuSpacing.snoozeSpacing) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(Text(verbatim: model.snoozeHeading))
                    .accessibilityAddTraits(.isHeader)
                if let timeLeft = model.snoozeTimeLeft {
                    Spacer(minLength: 8)
                    Text(verbatim: timeLeft)
                        .font(.appCallout)
                        .foregroundStyle(.appSecondary)
                        .monospacedDigit()
                }
            }
            HStack(spacing: 6) {
                ForEach(AutoPauseSnooze.allCases, id: \.self) { snooze in
                    let isRunning = snooze == model.runningSnoozeDuration
                    Button { model.perform(.snooze(snooze)) } label: {
                        Text(verbatim: snooze.shortTitle)
                            .font(.appCallout)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, MenuSpacing.chipVertical)
                    }
                    .buttonStyle(ChipButtonStyle(filled: true, isSelected: isRunning))
                    .accessibilityLabel(snooze.title)
                    .accessibilityAddTraits(isRunning ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, MenuSpacing.sectionVertical)
        .frame(width: menuContentWidth)
    }
}
