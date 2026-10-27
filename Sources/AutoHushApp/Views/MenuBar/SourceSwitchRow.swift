import SwiftUI
import AutoHushKit

/// An app with sound and a switch for whether it pauses your player, as
/// Playing Now and the ignored apps' side window list them: its icon, its
/// name and what it does now (`MenuSwitchRow`); one stop for VoiceOver, the
/// switch named by the app, what it does its hint.
struct SourceSwitchRow: View {
    let model: StatusMenuModel
    let source: AudioSource
    /// Ignored, it says only that: the ignored apps' side window, whose
    /// title says the rest (the user, 2026-10-18: the line wrapped there).
    var saysIgnoredShortly = false

    var body: some View {
        let pausesMusic = !model.status.isIgnored(source.id)
        let state = pausesMusic
            ? Text(verbatim: PlayerOption.interruptsLabel(mutes: model.status.mutesNow))
            : saysIgnoredShortly
            ? Text("Ignored", comment: "The menu's Ignored Apps side window: under each app that is ignored (the side window's title already says what that means)")
            : Text(verbatim: IgnoredText.label)
        return MenuSwitchRow(isOn: Binding(get: { !model.status.isIgnored(source.id) },
                                           set: { model.perform(.setIgnored(source, !$0)) }),
                             label: Text(verbatim: source.name), hint: state) {
            Image(nsImage: AppIcon.image(for: source, players: model.status.playerOptions, size: 20))
                .resizable()
                .frame(width: 20, height: 20)
        } title: {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: source.name).lineLimit(1)
                state
                    .font(.appCaption)
                    .foregroundStyle(.appSecondary)
            }
        }
    }
}
