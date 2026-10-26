import SwiftUI

/// The label of a row that opens something else: a symbol, its title, what
/// it's set to (if anything), and a chevron toward what it opens, mirrored
/// right to left, in the accent color. Behavior's rows to Fine-Tuning
/// (`FineTuningRow`) and the menu card's Change Player (`CardPlayerRow`).
struct ChevronRowLabel: View {
    let symbol: String
    let title: String
    var value: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.appSecondary)
                .accessibilityHidden(true)
            Text(verbatim: title)
            Spacer(minLength: 8)
            if let value {
                Text(verbatim: value)
                    .monospacedDigit()
                    .foregroundStyle(.appSecondary)
            }
            Image(systemName: "chevron.forward")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
