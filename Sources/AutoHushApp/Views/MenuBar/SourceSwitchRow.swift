import SwiftUI
import AutoHushKit

/// An app with sound and a switch for whether it pauses your player, as
/// Playing Now and the ignored apps' side window list them: its icon, its
/// name and what it does now; one stop for VoiceOver, the switch named by
/// the app, what it does its hint.
struct SourceSwitchRow: View {
    let model: StatusMenuModel
    let source: AudioSource
    @FocusState private var isFocused: Bool

    var body: some View {
        let pausesMusic = !model.status.isIgnored(source.id)
        let state = pausesMusic
            ? Text(verbatim: PlayerOption.interruptsLabel(mutes: model.status.playerMutes))
            : Text("Ignored — your player keeps playing", comment: "The menu's Playing Now and Settings → Sound Sources: under an app that is ignored, so your player keeps playing while it plays")
        return HStack(spacing: 8) {
            Image(nsImage: AppIcon.image(for: source, players: model.status.playerOptions, size: 20))
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: source.name).lineLimit(1)
                state
                    .font(.appCaption)
                    .foregroundStyle(.appSecondary)
            }
            .accessibilityHidden(true) // the switch says it: one stop for VoiceOver
            Spacer(minLength: 8)
            Toggle(isOn: Binding(get: { pausesMusic }, set: { model.perform(.setIgnored(source, !$0)) })) {
                Text(verbatim: source.name)
            }
            .toggleStyle(PillToggleStyle())
            .focused($isFocused)
            .focusEffectDisabled()
            .accessibilityHint(state)
        }
        // Highlighted by the arrow keys and the pointer; its switch takes the keyboard's focus (F5).
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .modifier(Highlightable(isFocused: isFocused, press: {
            model.perform(.setIgnored(source, !model.status.isIgnored(source.id)))
        }))
        .padding(.horizontal, -6)
        .padding(.vertical, -3)
    }
}
