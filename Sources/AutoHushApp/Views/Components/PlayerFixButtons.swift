import SwiftUI

/// What fixes the chosen player, under its status line in the menu's card
/// and in Settings → General: Reopen while it must be reopened to be
/// controlled (its tooltip and VoiceOver hint say why), Unmute while it's
/// muted for another app (it's heard until the other apps stop). `nil`:
/// not offered now. In the card they're its chips (`CardChip`), in Settings
/// push buttons; side by side or stacked, as the caller lays them out.
struct PlayerFixButtons: View {
    let player: String
    var reopen: (() -> Void)?
    var unmute: (() -> Void)?
    var inCard = false

    var body: some View {
        if let reopen {
            let reason = ReopenText.reason(player)
            button(AppStatus.reopenPlayerTitle, symbol: "arrow.clockwise", action: reopen)
                .help(reason)
                .accessibilityHint(Text(verbatim: reason))
        }
        if let unmute {
            button(AppStatus.unmuteTitle, symbol: "speaker.wave.2", action: unmute)
        }
    }

    @ViewBuilder private func button(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        if inCard {
            CardChip(title: Text(verbatim: title), symbol: symbol, action: action)
        } else {
            Button(action: action) {
                Label { Text(verbatim: title) } icon: { Image(systemName: symbol) }
            }
            .buttonStyle(.chip)
        }
    }
}
