import SwiftUI
import AutoHushKit

/// What AutoHush can do with the chosen player, each with a check or a dash:
/// its permission allowed, and whether it fades (or not, or fades are off).
/// Under the player's name in Settings → General and in the menu's card.
struct PlayerChecks: View {
    let model: SettingsModel

    var body: some View {
        if model.chosenPlayer != nil {
            HStack(spacing: 12) {
                if let control = model.permissions.control, model.permissions.controlAccess.isSatisfied {
                    check(Self.allowedTitle(control), done: true)
                }
                if !model.playerCanFade {
                    check(String(localized: "No fades", comment: "Settings → General and the foot of the menu's card, under the media player: AutoHush can't fade this player (TIDAL, Apple Podcasts, web apps)"), done: false)
                } else if model.timings.fadesEnabled {
                    check(FadesText.title, done: true)
                } else {
                    check(String(localized: "Fades off", comment: "Settings → General and the foot of the menu's card, under the media player: fades are turned off in Settings → Behavior"), done: false)
                }
            }
        }
    }

    private func check(_ text: String, done: Bool) -> some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(done ? AnyShapeStyle(.appSuccess) : AnyShapeStyle(.appSecondary))
        }
        .font(.appCaption)
        .foregroundStyle(.appSecondary)
    }

    private static func allowedTitle(_ permission: Permission) -> String {
        switch permission {
        case .automation:
            String(localized: "Automation allowed", comment: "Settings → General and the foot of the menu's card, under the media player, with a check: AutoHush may control it through Automation")
        default:
            String(localized: "Accessibility allowed", comment: "Settings → General and the foot of the menu's card, under the media player, with a check: AutoHush may control it through Accessibility")
        }
    }
}
