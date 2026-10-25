import SwiftUI

/// A Behavior card's last row (L4, the user's pick, 2026-10-25): its
/// settings in Fine-Tuning by name, with what they're set to, and a
/// chevron; a click, or Return and Space on its highlight, shows them there
/// (the keys' highlight going on from there).
struct FineTuningRow: View {
    let model: SettingsModel
    /// The card it shows.
    let part: FineTuningSettingsView.Part
    let title: String
    /// What they're set to ("0.5 s", "1 s out, 2 s in"); none while the
    /// switch they follow is off.
    let value: String?

    var body: some View {
        Button { model.showFineTuning(part) } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.appSecondary)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                Spacer(minLength: 8)
                if let value {
                    Text(verbatim: value)
                        .monospacedDigit()
                        .foregroundStyle(.appSecondary)
                }
                // Toward the page, mirrored right to left, in the accent color.
                Image(systemName: "chevron.forward")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .highlightableRow(press: { model.showFineTuning(part, byKeyboard: true) })
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: value ?? ""))
        .accessibilityHint(Text("Shows it in Fine-Tuning", comment: "VoiceOver hint of a row at the foot of a Settings → Behavior card, which opens the Fine-Tuning page at its settings"))
    }
}
