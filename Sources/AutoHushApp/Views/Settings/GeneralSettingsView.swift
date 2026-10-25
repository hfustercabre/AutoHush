import AppKit
import SwiftUI
import AutoHushKit

/// Settings → General, a grouped form: the media player, with the
/// Auto-Pause switch; every player as tiles, to choose another; then launch
/// at login and where the menu bar icon goes.
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
            Card(Text("Startup and Menu Bar", comment: "Settings → General: heading over the last section, with Launch at login and Keep icon next to system icons")) {
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
                CardDivider()
                SwitchRow(Text(verbatim: MenuBarIconPlace.title),
                          subtitle: Text("Where the notch or other apps’ icons can’t hide it. Turned off, ⌘-drag it where you like.",
                                         comment: "Settings → General, under Keep icon next to system icons; ⌘-drag is how macOS moves menu bar icons"),
                          isOn: Binding(get: { model.keepsMenuBarIconNearSystemIcons },
                                        set: { model.setKeepsMenuBarIconNearSystemIcons($0) }))
            }
        }
    }

    /// The chosen player with what it's doing (with Reopen or Unmute, as
    /// the menu's card has them) and what works; what it lacks and the way
    /// to allow it; a web app's controls; then the Auto-Pause switch.
    private var playerCard: some View {
        Card(Text(verbatim: MenuMediaPlayerView.title)) {
            HStack(alignment: .center, spacing: 12) {
                PlayerIcon(player: model.chosenPlayer, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: model.chosenPlayerName ?? PlayerOption.noneChosenLabel)
                        .font(.appHeadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: model.statusLine)
                        .font(.appSubheadline)
                        .foregroundStyle(model.statusNeedsAttention ? AnyShapeStyle(.appWarning) : AnyShapeStyle(.appSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                    if model.offersReopenPlayer || model.offersUnmute || model.showsResumeFailure {
                        // As the menu's card has them.
                        HStack(spacing: 8) {
                            PlayerFixButtons(player: model.chosenPlayerName ?? "",
                                             reopen: model.offersReopenPlayer ? { model.actions?.reopenPlayer() } : nil,
                                             unmute: model.offersUnmute ? { model.actions?.unmutePlayer() } : nil)
                            if model.showsResumeFailure {
                                Button { model.actions?.retryResume() } label: {
                                    Label { Text(verbatim: TryAgainText.title) } icon: { Image(systemName: "arrow.clockwise") }
                                }
                                .buttonStyle(.chip)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    // What works: the permission the player needs, once allowed, and whether it fades.
                    PlayerChecks(model: model).padding(.top, 2)
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
                Text(verbatim: AutoPauseText.title),
                subtitle: Text("Choose which apps pause your player on the Sound Sources page.",
                               comment: "Settings → General, under the Auto-Pause switch; Sound Sources is the Settings page that lists them"),
                isOn: Binding(get: { model.isAutoPauseOn }, set: { model.settings.setAutoPause($0) })
            )
            if let note = model.autoPauseNote {
                Text(note).captionStyle()
            }
        }
    }
}
