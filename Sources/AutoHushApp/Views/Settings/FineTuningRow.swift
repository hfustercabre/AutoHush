import AppKit
import SwiftUI

/// A Behavior card's last row (L4, the user's pick, 2026-10-25), and Media
/// Player's Controls row (F5, 2026-11-05): its settings in Fine-Tuning by
/// name, with what they're set to, and a chevron; a click, or Return and
/// Space on its highlight, shows them there (the keys' highlight going on
/// from there). Pressed by VoiceOver, it takes the keys' way, so VoiceOver's
/// cursor goes to the card's first row, not left on the row that's gone (N8,
/// the a11y audit, 2026-11-06).
struct FineTuningRow: View {
    let model: SettingsModel
    /// The Fine-Tuning card it shows.
    let card: SettingsCard
    let title: String
    /// What they're set to ("0.5 s", "1 s out, 2 s in"); none while the
    /// switch they follow is off.
    let value: String?

    var body: some View {
        Button { model.showFineTuning(card, byKeyboard: NSWorkspace.shared.isVoiceOverEnabled) } label: {
            ChevronRowLabel(symbol: "slider.horizontal.3", title: title, value: value)
        }
        .buttonStyle(.plain)
        .highlightableRow(press: { model.showFineTuning(card, byKeyboard: true) })
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: value ?? ""))
        .accessibilityHint(Text("Shows it in Fine-Tuning", comment: "VoiceOver hint of a row at the foot of a Settings → Behavior card, or of Settings → Media Player's “Controls” row, which opens the Fine-Tuning page at its settings"))
    }
}
