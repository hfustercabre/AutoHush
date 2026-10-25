import SwiftUI

/// The card's last row (H4, the user's pick, 2026-10-25, in place of the
/// Media Player part under the card): "Change Player", or "Choose Player"
/// while none is chosen, between a list symbol and a chevron. As Ignored
/// Apps' row, a click or the pointer resting on it opens the players in a
/// side window beside the menu, level with it, and it's lit while that's
/// open. Its own button: a click on it doesn't turn Auto-Pause on or off.
struct CardPlayerRow: View {
    let model: StatusMenuModel

    var body: some View {
        let open = { model.perform(.openSide(.players)) }
        Button(action: open) {
            HStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .foregroundStyle(.appSecondary)
                    .accessibilityHidden(true)
                Text(verbatim: model.status.chosenPlayer == nil ? Self.chooseTitle : Self.changeTitle)
                Spacer(minLength: 8)
                // Toward the side window, mirrored right to left, in the
                // accent color as Ignored Apps' (the user, 2026-10-21).
                Image(systemName: "chevron.forward")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            .font(.appCallout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(HighlightableControl(cornerRadius: 6, outset: 4, isLit: model.isChoosingPlayer, press: open, opensSide: true))
        .onHover { model.perform(.hoverSideRow(.players, $0)) }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { model.sideRowTops[.players] = $0 }
        .accessibilityValue(model.isChoosingPlayer ? AccessibilityText.expanded : AccessibilityText.collapsed)
    }

    static var changeTitle: String {
        String(localized: "Change Player", comment: "The menu: the last row of the card at the top, under the media player's name; opens every player beside the menu, to choose another")
    }

    static var chooseTitle: String {
        String(localized: "Choose Player", comment: "The menu: the last row of the card at the top while no media player is chosen; opens every player beside the menu")
    }
}
