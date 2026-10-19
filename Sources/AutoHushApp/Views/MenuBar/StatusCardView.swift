import AppKit
import SwiftUI
import AutoHushKit

/// The card at the top of the menu, which stays put while the rest scrolls:
/// the media player, what's happening and the Auto-Pause switch, then what
/// AutoHush can do with the player, as Settings → General shows it
/// (`PlayerChecks`, K3, the user's pick, 2026-10-18) (the player's choice is
/// under it, `MenuMediaPlayerView`). The whole card is Auto-Pause's (the
/// user, 2026-10-18: "add that little accent color to the whole box. Also,
/// a click on the box should toggle Auto-Pause"): the menu's highlight and
/// the switch's focus tint all of it, and a click anywhere on it but on its
/// own buttons turns Auto-Pause on or off.
struct StatusCardView: View {
    let model: StatusMenuModel
    /// For the player's checks; none in a menu without Settings' model.
    var settings: SettingsModel?
    @FocusState private var autoPauseFocused: Bool

    private var status: AppStatus { model.status }

    var body: some View {
        Card(clearGlass: true) {
            HStack(spacing: 10) {
                PlayerIcon(player: status.chosenPlayer, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: status.cardTitle)
                        .font(.appHeadline)
                        .lineLimit(1)
                    // What's happening. When the player couldn't be controlled,
                    // an info symbol ends it, and a click on it tells why.
                    if status.controlError != nil {
                        Button { model.perform(.showControlError) } label: { statusLine(withInfo: true) }
                            .buttonStyle(.plain)
                            .modifier(HighlightableControl(cornerRadius: 6, press: { model.perform(.showControlError) }))
                            .help(Self.whyLabel)
                            .accessibilityLabel(Text(verbatim: status.statusLine))
                            .accessibilityHint(Text(verbatim: Self.whyLabel))
                    } else {
                        statusLine(withInfo: false)
                    }
                    if status.canRetry { retryButton }
                    if let missing = status.missingPermission { allowButton(missing) }
                    PlayerFixButtons(player: status.playerName,
                                     reopen: status.playerNeedsReopen && status.isReady ? { model.perform(.reopenPlayer) } : nil,
                                     unmute: status.offersUnmute ? { model.perform(.unmutePlayer) } : nil,
                                     inCard: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Toggle(isOn: Binding(get: { status.autoPause == .on }, set: { _ in model.perform(.toggleAutoPause) })) {
                        Text(verbatim: AutoPauseText.title)
                    }
                    .toggleStyle(PillToggleStyle())
                    .controlSize(MenuSpacing.switchSize)
                    .focused($autoPauseFocused)
                    .focusEffectDisabled() // the whole card shows it
                    Text(verbatim: AutoPauseText.title)
                        .font(.appCaption)
                        .foregroundStyle(.appSecondary)
                        .fixedSize() // whole, in every language: the status line wraps instead
                        .accessibilityHidden(true)
                }
            }
            // What AutoHush can do with it: its permission allowed, its fades.
            if let settings, settings.chosenPlayer != nil {
                CardDivider()
                PlayerChecks(model: settings)
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
        .contentShape(RoundedRectangle(cornerRadius: ClearGlassCard.cornerRadius, style: .continuous))
        .onTapGesture { model.perform(.toggleAutoPause) }
        .modifier(Highlightable(isFocused: autoPauseFocused, lightsItself: true, // the tint over the glass (`Card`)
                                press: { model.perform(.toggleAutoPause) }))
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .frame(width: menuContentWidth)
        // After Retry, VoiceOver hears how it went, once the start is over.
        .onChange(of: status.statusLine) { _, line in
            guard model.announcesRetryOutcome, status.health != .starting else { return }
            model.announcesRetryOutcome = false
            AccessibilityNotification.Announcement(line).post()
        }
    }

    /// The status line, in orange when something needs the user; with an
    /// info symbol after its last word (the line then opens the alert that
    /// says why the player couldn't be controlled; the menu closes first).
    private func statusLine(withInfo: Bool) -> some View {
        let line = Text(verbatim: status.statusLine)
            .foregroundStyle(status.needsAttention ? AnyShapeStyle(.appWarning) : AnyShapeStyle(.appSecondary))
        let info = Text(Image(systemName: "info.circle")).foregroundStyle(.appSecondary)
        // A no-break space: the symbol never ends up alone on a line. By
        // interpolation, each part keeping its color (`+` is deprecated from
        // the macOS 26 SDK on).
        return (withInfo
                ? Text("\(line)\u{00A0}\(info)", comment: "The menu's status line (the first %@, already translated) and an info symbol after it (the second %@), joined by a no-break space so the symbol stays with the last word: keep it as it is")
                : line)
            .font(.appSubheadline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static var whyLabel: String {
        String(localized: "Why?", comment: "Tooltip and VoiceOver hint of the menu's status line when the media player couldn't be controlled: a click shows why")
    }

    /// Asks for the permission its line says is missing (or reopens
    /// AutoHush, once Audio Recording only needs that); VoiceOver hears what
    /// it allows.
    @ViewBuilder private func allowButton(_ permission: Permission) -> some View {
        if status.offersReopen {
            CardChip(title: Text(verbatim: PermissionText.reopen), symbol: "arrow.clockwise") { model.perform(.reopenAutoHush) }
        } else {
            CardChip(title: Text(verbatim: AddAppText.allowButton), symbol: "hand.raised") {
                model.perform(.resolveWarning(permission))
            }
            .accessibilityLabel(Text(verbatim: permission.grantTitle))
        }
    }

    /// Tries starting again; the menu stays open and the card shows how it went.
    private var retryButton: some View {
        CardChip(title: Text(TryAgainText.title),
                 symbol: "arrow.clockwise") { model.perform(.retry) }
    }
}
