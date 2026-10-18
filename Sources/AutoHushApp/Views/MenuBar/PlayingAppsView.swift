import SwiftUI
import AutoHushKit

/// "Playing Now": each app playing sound, with a switch for whether it
/// pauses the music; or "Recently Played", the same for the apps that
/// played in the last 30 minutes.
struct PlayingAppsView: View {
    enum List { case playingNow, recentlyPlayed }

    let model: StatusMenuModel
    let list: List

    private var title: Text {
        switch list {
        case .playingNow: Text("Playing Now", comment: "Menu: heading of the apps playing sound right now")
        case .recentlyPlayed: Text("Recently Played", comment: "Menu: heading of the apps that played sound in the last 30 minutes, under Playing Now")
        }
    }

    private var sources: [AudioSource] {
        list == .playingNow ? model.listedSources : model.listedRecentSources
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
                .accessibilityAddTraits(.isHeader)
            ForEach(sources, id: \.self) { source in
                row(source, pausesMusic: !model.status.isIgnored(source.id))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: menuContentWidth)
    }

    private func row(_ source: AudioSource, pausesMusic: Bool) -> some View {
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
            .accessibilityHint(state)
        }
    }
}
