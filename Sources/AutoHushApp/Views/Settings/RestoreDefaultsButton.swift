import SwiftUI

/// A card's Restore Defaults, under it on the right: it sets the card's own
/// settings back, and shows only once one differs from its default (RD1,
/// the user's pick, 2026-10-26: a dimmed one under every card was clutter).
/// Gone once pressed, so VoiceOver says the card was restored, and a press
/// from the arrow keys' highlight leaves it on the card's first row (U2,
/// the user, 2026-10-27).
struct RestoreDefaultsButton: View {
    let model: SettingsModel
    let card: SettingsCard
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?
    @Environment(\.highlightGroup) private var group

    var body: some View {
        if !model.isDefault(card) { button }
    }

    private var button: some View {
        HStack {
            Spacer()
            Button(action: restore) {
                Text("Restore Defaults", comment: "Settings: the button under each card with settings (Behavior's, Fine-Tuning's, General's Startup and Menu Bar, About's Updates) that sets that card's settings back to their defaults")
            }
                .buttonStyle(.chip)
        }
        .padding(.top, 6)
    }

    private func restore() {
        let byKeys = keyboard?.isPressing == true
        model.restoreDefaults(card)
        AccessibilityNotification.Announcement(Self.restoredAnnouncement).post()
        if byKeys, let group { keyboard?.highlightFirst(in: group) }
    }

    static var restoredAnnouncement: String {
        String(localized: "Restored", comment: "VoiceOver, after Restore Defaults under a Settings card: the card's settings are back to their defaults")
    }
}
