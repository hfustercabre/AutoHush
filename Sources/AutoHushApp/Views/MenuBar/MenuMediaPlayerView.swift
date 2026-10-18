import AppKit
import SwiftUI

/// The media player's part, first under the menu's card (V5, the user's
/// pick, 2026-10-18), as the settings' parts: "Media Player" over a row with
/// the chosen player's icon, its name and what kind of player it is, and a
/// chevron; a click unfolds the players under it (`MenuPlayerListView`) and
/// folds them again.
struct MenuMediaPlayerView: View {
    let model: StatusMenuModel

    private var status: AppStatus { model.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuPartTitle(Text("Media Player", comment: "Settings → General, Diagnostics and the menu: heading over the media player"))
            MenuFoldingRow(title: status.chosenPlayer?.name ?? Self.chooseTitle, subtitle: subtitle,
                           isOpen: model.isChoosingPlayer, action: { model.perform(.togglePlayerList) }) {
                playerIcon
            }
            if model.isChoosingPlayer {
                MenuPlayerListView(model: model)
                    .padding(.horizontal, 14)
                    .transition(.opacity)
            }
        }
        .frame(width: menuContentWidth)
    }

    private static var chooseTitle: String {
        String(localized: "Choose…", comment: "The menu: under Media Player, while no media player is chosen; a click unfolds them")
    }

    /// What kind of player it is, or why it can't play now.
    private var subtitle: String? {
        guard let player = status.chosenPlayer else { return nil }
        if !player.isInstalled { return PlayerOption.notInstalledLabel }
        if player.pausesByMuting { return PlayerOption.mutedInsteadLabel }
        return switch player.kind {
        case .app:
            String(localized: "Supported app", comment: "The menu, under the chosen media player's name: an app AutoHush supports itself (one of the “Supported Apps”)")
        case .safariWebApp:
            String(localized: "Safari web app", comment: "The menu, under the chosen media player's name: a website added to the Dock from Safari")
        case .checkedApp:
            String(localized: "Added with Add an App", comment: "The menu, under the chosen media player's name: an app the user added through Add an App's check")
        }
    }

    /// The chosen player's icon, faded while it isn't installed.
    @ViewBuilder private var playerIcon: some View {
        if let player = status.chosenPlayer {
            Image(nsImage: player.icon(size: 22))
                .resizable()
                .frame(width: 22, height: 22)
                .opacity(player.isInstalled ? 1 : 0.5)
        } else {
            Image(systemName: "music.note")
                .font(.body.weight(.semibold))
                .foregroundStyle(.appSecondary)
        }
    }
}
