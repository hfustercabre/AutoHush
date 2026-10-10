import AppKit
import SwiftUI

/// The card at the top of the menu: the music player, what's happening, the
/// Auto-Pause switch, and the music player choice.
struct StatusCardView: View {
    let model: StatusMenuModel

    private var status: AppStatus { model.status }

    var body: some View {
        Card(padding: 10) {
            HStack(spacing: 10) {
                playerIcon(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: status.cardTitle)
                        .font(.appHeadline)
                        .lineLimit(1)
                    // What's happening. When the player couldn't be controlled,
                    // an info symbol ends it, and a click on it tells why.
                    if status.controlError != nil {
                        Button { model.perform(.showControlError) } label: { statusLine(withInfo: true) }
                            .buttonStyle(.plain)
                            .help(Self.whyLabel)
                            .accessibilityLabel(Text(verbatim: status.statusLine))
                            .accessibilityHint(Text(verbatim: Self.whyLabel))
                    } else {
                        statusLine(withInfo: false)
                    }
                    if status.canRetry { retryButton }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Toggle(isOn: Binding(get: { status.autoPause == .on }, set: { _ in model.perform(.toggleAutoPause) })) {
                        Text("Auto-Pause", comment: "The switch that turns auto-pause on and off: its label in the menu's card and Settings → General, and a Diagnostics row")
                    }
                    .toggleStyle(PillToggleStyle())
                    Text("Auto-Pause", comment: "The switch that turns auto-pause on and off: its label in the menu's card and Settings → General, and a Diagnostics row")
                        .font(.appCaption)
                        .foregroundStyle(.appSecondary)
                        .fixedSize() // whole, in every language: the status line wraps instead
                        .accessibilityHidden(true)
                }
            }
            CardDivider()
            HStack(spacing: 6) {
                SectionLabel(Text("Media player", comment: "The menu's card and Settings → General: label of the chosen media player"))
                Spacer(minLength: 4)
                playerButton
            }
            // A web app's controls: learned or not, and the way to learn
            // them in the learning window (the steps show only there).
            if status.canLearnControlsAgain {
                CardDivider()
                ControlsRow(name: status.playerName, isLearned: status.learning?.isLearned == true, buttonFont: .appCallout) {
                    model.perform(.learnControls)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .frame(width: menuContentWidth)
    }

    /// The status line, in orange when something needs the user; with an
    /// info symbol after its last word (the line then opens the alert that
    /// says why the player couldn't be controlled; the menu closes first).
    private func statusLine(withInfo: Bool) -> some View {
        let line = Text(verbatim: status.statusLine)
            .foregroundStyle(status.needsAttention ? AnyShapeStyle(.appWarning) : AnyShapeStyle(.appSecondary))
        let info = Text(Image(systemName: "info.circle")).foregroundStyle(.appSecondary)
        // A no-break space: the symbol never ends up alone on a line.
        return (withInfo ? line + Text(verbatim: "\u{00A0}") + info : line)
            .font(.appSubheadline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static var whyLabel: String {
        String(localized: "Why?", comment: "Tooltip and VoiceOver hint of the menu's status line when the media player couldn't be controlled: a click shows why")
    }

    /// Tries starting again; the menu stays open and the card shows how it went.
    private var retryButton: some View {
        Button { model.perform(.retry) } label: {
            Label {
                Text("Retry", comment: "Menu: button on the card that tries starting again after a problem")
            } icon: {
                Image(systemName: "arrow.clockwise")
            }
            .font(.appCallout)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
        }
        .buttonStyle(ChipButtonStyle(filled: true, cornerRadius: 6))
        .padding(.top, 4)
    }

    /// The chosen player, or "Choose…"; unfolds the players under the card.
    private var playerButton: some View {
        Button { model.perform(.togglePlayerList) } label: {
            HStack(spacing: 6) {
                if status.chosenPlayer != nil { playerIcon(size: 16) }
                Text(verbatim: status.chosenPlayer?.name ?? String(localized: "Choose…", comment: "The menu's card, on the button that unfolds the media players, while none is chosen"))
                    .font(.appCallout)
                Image(systemName: model.isChoosingPlayer ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.appSecondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
        .buttonStyle(ChipButtonStyle(cornerRadius: 6))
        .padding(.trailing, -6)
    }

    /// The chosen player's icon; AutoHush's own while none is chosen, and
    /// faded while the chosen player isn't installed.
    private func playerIcon(size: CGFloat) -> some View {
        let image: NSImage
        let installed = status.chosenPlayer?.isInstalled ?? true
        if let player = status.chosenPlayer {
            image = player.icon(size: size)
        } else {
            image = NSApp.applicationIconImage ?? AppIcon.image(bundlePath: nil, size: size)
        }
        return Image(nsImage: image)
            .resizable()
            .frame(width: size, height: size)
            .opacity(installed ? 1 : 0.5)
            .accessibilityHidden(true)
    }
}
