import SwiftUI
import AutoHushKit

/// The side window beside the menu (W2, the user's pick, 2026-10-18), as a
/// submenu: Media Player's players under their title (`MenuPlayerListView`),
/// or the ignored apps under theirs, each with its switch (`SourceSwitchRow`).
/// It scrolls when it's taller than the screen leaves, its last rows fading
/// over a chevron while more is below, as the menu's (`MenuScrollArea`); it
/// reports its height to its window (`onHeight`).
struct MenuSidePanelView: View {
    let model: StatusMenuModel
    let onHeight: @MainActor (CGFloat) -> Void

    static let width: CGFloat = 300

    var body: some View {
        MenuScrollArea(isCapped: model.isSideCappedByScreen, revealed: model.sideKeyboard.revealed, onHeight: onHeight) {
            VStack(alignment: .leading, spacing: 0) {
                switch model.openSide {
                // Each title as far over its first row as Playing Now's is (the user, 2026-10-18).
                case .players?:
                    MenuPartTitle(Text(verbatim: MenuMediaPlayerView.title))
                        .padding(.bottom, MenuSpacing.playingSpacing)
                    MenuPlayerListView(model: model)
                        .padding(.horizontal, 14)
                case .ignoredApps?:
                    MenuPartTitle(Text(verbatim: MenuIgnoredAppsView.title))
                        .padding(.bottom, MenuSpacing.playingSpacing)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.listedIgnoredApps, id: \.self) { source in
                            SourceSwitchRow(model: model, source: source, saysIgnoredShortly: true)
                        }
                        // Several at once (the user, 2026-10-18); the menu closes for the
                        // panel. Its text in line with the apps' names (U4, 2026-10-19).
                        MenuActionRow(place: .sideWindow, action: { model.perform(.ignoreAnotherApp) }) {
                            Image(systemName: "plus.circle").accessibilityHidden(true)
                        } content: {
                            Text(verbatim: IgnoreAppsPicker.title)
                        }
                    }
                    .padding(.horizontal, 14)
                case nil:
                    EmptyView()
                }
            }
            .padding(.vertical, 8)
            .frame(width: Self.width, alignment: .leading)
        }
        .font(.appBody)
        .environment(\.isInMenu, true)
        .environment(model.sideKeyboard)
        .environment(\.controlActiveState, .key) // as the menu's (`MenuPanelView`)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
