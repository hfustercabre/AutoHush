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
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(width: menuContentWidth)
    }
}
