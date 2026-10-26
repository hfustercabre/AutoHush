import SwiftUI

/// A card's Restore Defaults, under it on the right: it sets the card's own
/// settings back, and shows only once one differs from its default (RD1,
/// the user's pick, 2026-10-26: a dimmed one under every card was clutter).
struct RestoreDefaultsButton: View {
    let model: SettingsModel
    let card: SettingsCard

    var body: some View {
        if !model.isDefault(card) { button }
    }

    private var button: some View {
        HStack {
            Spacer()
            Button { model.restoreDefaults(card) } label: {
                Text("Restore Defaults", comment: "Settings: the button under each card with settings (Behavior's, Fine-Tuning's, General's Startup and Menu Bar, About's Updates) that sets that card's settings back to their defaults")
            }
                .buttonStyle(.chip)
        }
        .padding(.top, 6)
    }
}
