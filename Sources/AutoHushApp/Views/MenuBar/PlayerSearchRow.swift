import SwiftUI

/// The search above the unfolded music players, shown from
/// `PlayerOption.searchThreshold` players on: typing narrows them down. It
/// takes the keyboard as the players unfold (`StatusMenuController` gives it
/// to it), so typing goes straight to it.
struct PlayerSearchRow: View {
    let model: StatusMenuModel

    var body: some View {
        SearchField(text: Binding(
            get: { model.playerSearch },
            set: { model.perform(.searchPlayers($0)) }
        ))
        // Arriving, it fades in and drifts down into place, as More Settings'
        // rows do; only those animate (`MoreSettingsRowView`).
        .animation(.spring(duration: 0.35, bounce: 0.2)) { view in
            view.opacity(model.playerSearchArrived ? 1 : 0).offset(y: model.playerSearchArrived ? 0 : -8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(width: menuContentWidth)
    }
}
