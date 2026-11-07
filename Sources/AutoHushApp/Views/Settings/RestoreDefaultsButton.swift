import SwiftUI

/// A card's Restore Defaults, under it on the right: it sets the card's own
/// settings back, and shows only once one differs from its default (RD1,
/// the user's pick, 2026-10-26: a dimmed one under every card was clutter).
/// Gone once pressed, so VoiceOver says the card was restored, and a press
/// from the arrow keys' highlight leaves it on the card's first row (U2,
/// the user, 2026-10-27), and so does one while VoiceOver is on, whose cursor
/// would stay on the button that's gone (N8, the a11y audit, 2026-11-06).
/// VoiceOver reads it with the card's title, since a page can show five
/// (I3, the user, 2026-10-27). Each press is a step for
/// the Edit menu's Undo (U10a, 2026-11-02: `SettingsModel.restoreDefaults`).
struct RestoreDefaultsButton: View {
    let model: SettingsModel
    let card: SettingsCard
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?
    @Environment(\.highlightGroup) private var group
    @Environment(\.cardTitle) private var cardTitle
    @Environment(\.voiceOver) private var voiceOver

    var body: some View {
        if !model.isDefault(card) { button }
    }

    private var button: some View {
        HStack {
            Spacer()
            Button(action: restore) { Self.title }
                .buttonStyle(.chip)
                .accessibilityLabel(accessibilityName)
        }
        .padding(.top, 6)
    }

    private func restore() {
        let movesHighlight = Self.movesHighlight(keyboard: keyboard, voiceOver: voiceOver)
        model.restoreDefaults(card)
        if movesHighlight, let group { keyboard?.highlightFirst(in: group) }
        // At high priority: the highlight's move, which VoiceOver follows,
        // would cut a plain announcement off (the review of N8, 2026-11-06).
        postStepAnnouncement(Self.restoredAnnouncement)
    }

    /// Whether a press leaves the highlight on the card's first row: one
    /// by the keys, or with VoiceOver on (U2, N8); not a click's.
    static func movesHighlight(keyboard: KeyHighlight?, voiceOver: VoiceOverSetting) -> Bool {
        keyboard?.isPressing == true || voiceOver.isOn()
    }

    private static var title: Text {
        Text(verbatim: ButtonText.restoreDefaults)
    }

    /// The button's name for VoiceOver: with the card's title.
    private var accessibilityName: Text {
        guard let cardTitle else { return Self.title }
        return Text("Restore Defaults, \(cardTitle)", comment: "VoiceOver: the Restore Defaults button under a Settings card, named with the card it sets back; %@ is the card's title, e.g. Pausing")
    }

    static var restoredAnnouncement: String {
        String(localized: "Restored", comment: "VoiceOver, after Restore Defaults under a Settings card: the card's settings are back to their defaults")
    }
}
