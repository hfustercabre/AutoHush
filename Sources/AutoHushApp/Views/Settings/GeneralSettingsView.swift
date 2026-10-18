import AppKit
import SwiftUI
import AutoHushKit

/// Settings → General, a grouped form: the media player, with the
/// Auto-Pause switch; every player as tiles, to choose another; then launch
/// at login.
struct GeneralSettingsView: View {
    let model: SettingsModel

    private static var approvalNote: String {
        String(localized: "macOS is waiting for you to allow AutoHush in Login Items.",
               comment: "Settings → General, under Launch at login, while macOS waits for the user's approval in Login Items")
    }

    private func controlNote(_ permission: Permission, access: PermissionAccess) -> String {
        let name = model.chosenPlayerName ?? ""
        switch (permission, access) {
        case (_, .playerNotRunning):
            return PermissionText.controlNote(name, .playerNotRunning)
        case (.automation, _):
            return String(localized: "AutoHush can’t control \(name) without Automation access.",
                          comment: "Settings → General, under the media player, while Automation isn't allowed; %@ is the player")
        default:
            return String(localized: "AutoHush can’t control \(name) without Accessibility access.",
                          comment: "Settings → General, under the media player, while Accessibility isn't allowed; %@ is the player")
        }
    }

    var body: some View {
        SettingsPageScroll {
            playerCard
            PlayerTiles(options: model.offeredPlayers, selection: model.chosenPlayerID,
                        onSelect: { model.actions?.choosePlayer($0.bundleID) }, onAddWebApp: { model.actions?.openAddWebApp() },
                        onAddApp: { model.actions?.openAddApp() },
                        onRemove: { model.actions?.removeAddedApp($0.bundleID) })
            Card {
                SwitchRow(Text("Launch at login", comment: "Settings → General and Diagnostics: whether AutoHush opens when you log in"), isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let note = model.launchAtLoginError ?? (model.launchAtLoginNeedsApproval ? Self.approvalNote : nil) {
                    NoteLabel(note)
                    Button { model.openLoginItemsSettings() } label: {
                        Text("Open Login Items Settings…", comment: "Settings → General: button that opens System Settings → Login Items")
                    }
                        .buttonStyle(.chip)
                }
            }
        }
    }

    /// The chosen player with what it's doing (with Reopen or Unmute, as
    /// the menu's card has them) and what works; what it lacks and the way
    /// to allow it; a web app's controls; then the Auto-Pause switch.
    private var playerCard: some View {
        Card(Text("Media Player", comment: "Settings → General, Diagnostics and the menu: heading over the media player")) {
            HStack(alignment: .center, spacing: 12) {
                playerIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: model.chosenPlayerName ?? PlayerOption.noneChosenLabel)
                        .font(.appHeadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: model.statusLine)
                        .font(.appSubheadline)
                        .foregroundStyle(model.statusNeedsAttention ? AnyShapeStyle(.appWarning) : AnyShapeStyle(.appSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                    if model.offersReopenPlayer || model.offersUnmute {
                        playerButtons.padding(.vertical, 4)
                    }
                    checks.padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            // What the chosen player needs and lacks, and the way to allow it.
            if let control = model.permissions.control, !model.permissions.controlAccess.isSatisfied {
                NoteLabel(controlNote(control, access: model.permissions.controlAccess))
                PermissionButton(model: model, permission: control, access: model.permissions.controlAccess, long: true)
            }
            // A web app's controls: learned or not, and the way to learn them
            // afresh in the learning window (the steps show only there).
            if let name = model.chosenPlayerName, model.canLearnControlsAgain {
                CardDivider()
                ControlsRow(name: name, isLearned: model.learning?.isLearned == true) { model.actions?.learnControlsAgain() }
            }
            CardDivider()
            SwitchRow(
                Text("Auto-Pause", comment: "Auto-Pause, the feature's name: the switch's label in the menu's card and Settings → General, a Diagnostics row, the Focus filter's name, and the name of the Focus filter's On/Off choice"),
                subtitle: Text("Choose which apps pause your player on the Sound Sources page.",
                               comment: "Settings → General, under the Auto-Pause switch; Sound Sources is the Settings page that lists them"),
                isOn: Binding(get: { model.isAutoPauseOn }, set: { model.settings.setAutoPause($0) })
            )
            if let note = model.autoPauseNote {
                Text(note).captionStyle()
            }
        }
    }

    /// Under the status line, as in the menu's card: Reopen while the player
    /// needs reopening, Unmute while it's muted for another app.
    private var playerButtons: some View {
        HStack(spacing: 8) {
            if model.offersReopenPlayer {
                let reason = AddAppText.reopenReason(model.chosenPlayerName ?? "")
                Button { model.actions?.reopenPlayer() } label: {
                    Label { Text(verbatim: AppStatus.reopenPlayerTitle) } icon: { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(.chip)
                .help(reason)
                .accessibilityHint(Text(verbatim: reason))
            }
            if model.offersUnmute {
                Button { model.actions?.unmutePlayer() } label: {
                    Label { Text(verbatim: AppStatus.unmuteTitle) } icon: { Image(systemName: "speaker.wave.2") }
                }
                .buttonStyle(.chip)
            }
        }
    }

    /// The chosen player's icon (its placeholder while it isn't installed,
    /// faded), or AutoHush's while none is chosen.
    private var playerIcon: some View {
        let image = model.chosenPlayer?.icon(size: 56) ?? NSApp.applicationIconImage ?? NSImage()
        return Image(nsImage: image)
            .resizable()
            .frame(width: 56, height: 56)
            .opacity(model.chosenPlayer?.isInstalled == false ? 0.5 : 1)
            .accessibilityHidden(true)
    }

    /// Under the status line: the permission the player needs, once allowed,
    /// and whether the music fades.
    @ViewBuilder private var checks: some View {
        PlayerChecks(model: model)
    }
}
