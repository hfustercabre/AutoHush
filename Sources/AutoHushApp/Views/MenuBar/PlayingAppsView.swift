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
                SourceSwitchRow(model: model, source: source)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: menuContentWidth)
    }
}
