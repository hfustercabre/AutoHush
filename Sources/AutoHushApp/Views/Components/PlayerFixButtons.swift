import SwiftUI

/// What fixes the chosen player, under its status line in the menu's card
/// and in Settings → General: Reopen while it must be reopened to be
/// controlled (its tooltip and VoiceOver hint say why, and a caption under
/// it while the keys are on it, A13a), Unmute while it's
/// muted for another app (it's heard until the other apps stop), Try Again
/// after a given-up resume, then Learn Controls… while a web app's controls
/// aren't learned (`AppStatus.controlsNotLearned`; it opens the learning
/// window, as the Controls row's button does). `nil`: not offered now. In
/// the card they're its chips (`CardChip`), in Settings push buttons; side
/// by side or stacked, as the caller lays them out. The card has its Try Again above
/// the permission it lacks (`tryAgain(inCard:action:)`), not here.
struct PlayerFixButtons: View {
    let player: String
    var reopen: (() -> Void)?
    var unmute: (() -> Void)?
    var retryResume: (() -> Void)?
    var learnControls: (() -> Void)?
    var inCard = false

    var body: some View {
        if let reopen {
            let reason = ReopenText.reason(player)
            HighlightReasonCaption {
                Self.button(AppStatus.reopenPlayerTitle, symbol: "arrow.clockwise", inCard: inCard, action: reopen)
                    .help(reason)
                    .accessibilityHint(Text(verbatim: reason))
                    .highlightReason(reason)
            }
        }
        if let unmute {
            Self.button(AppStatus.unmuteTitle, symbol: "speaker.wave.2", inCard: inCard, action: unmute)
        }
        if let retryResume {
            Self.tryAgain(inCard: inCard, action: retryResume)
        }
        if let learnControls {
            Self.button(LearnText.learnButton, symbol: "hand.tap", inCard: inCard, action: learnControls)
        }
    }

    /// Try Again after a given-up resume, as a chip of the card or a button of Settings.
    static func tryAgain(inCard: Bool, action: @escaping () -> Void) -> some View {
        button(TryAgainText.title, symbol: "arrow.clockwise", inCard: inCard, action: action)
    }

    @ViewBuilder private static func button(_ title: String, symbol: String, inCard: Bool,
                                            action: @escaping () -> Void) -> some View {
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
