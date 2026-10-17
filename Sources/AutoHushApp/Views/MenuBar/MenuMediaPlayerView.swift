import AppKit
import SwiftUI

/// The media player's row under the menu's card (S5, the user's pick,
/// 2026-10-18), as Ignored Apps' row: a note symbol, "Media player", the
/// chosen player (its icon and its name in grey) and a chevron; a click
/// unfolds the players under it (`MenuPlayerListView`) and folds them again.
struct MenuMediaPlayerView: View {
    let model: StatusMenuModel

    private var status: AppStatus { model.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { model.perform(.togglePlayerList) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text("Media player", comment: "The menu's card and Settings → General: label of the chosen media player")
                    Spacer(minLength: 6)
                    if status.chosenPlayer != nil { playerIcon }
                    Text(verbatim: status.chosenPlayer?.name ?? String(localized: "Choose…", comment: "The menu's card, on the button that unfolds the media players, while none is chosen"))
                        .foregroundStyle(.appSecondary)
                        .lineLimit(1)
                    Image(systemName: model.isChoosingPlayer ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appSecondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(MenuRowButtonStyle())
            .accessibilityValue(model.isChoosingPlayer ? AccessibilityText.expanded : AccessibilityText.collapsed)
            if model.isChoosingPlayer {
                MenuPlayerListView(model: model)
                    .padding(.horizontal, 6)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(width: menuContentWidth)
    }

    /// The chosen player's icon, faded while it isn't installed.
    private var playerIcon: some View {
        Image(nsImage: status.chosenPlayer?.icon(size: 16) ?? NSImage())
            .resizable()
            .frame(width: 16, height: 16)
            .opacity(status.chosenPlayer?.isInstalled == false ? 0.5 : 1)
            .accessibilityHidden(true)
    }
}
