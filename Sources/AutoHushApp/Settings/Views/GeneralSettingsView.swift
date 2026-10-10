import AppKit
import SwiftUI
import AutoHushKit

/// Settings → General, in cards like the menu's: the media player, with the
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
            PlayerTiles(options: model.playerOptions.offered, selection: model.chosenPlayerID,
                        onSelect: { model.chooseMusicPlayer($0.bundleID) }, onAddWebApp: { model.addWebApp() })
            if model.playerOptions.noneInstalled {
                NoteLabel(PlayerOption.noneInstalledWarning)
            }
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

    /// The chosen player with what it's doing and what works; what it lacks
    /// and the way to allow it; a web app's controls; then the Auto-Pause
    /// switch.
    private var playerCard: some View {
        Card {
            HStack(alignment: .center, spacing: 12) {
                playerIcon
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel(Text("Media player", comment: "The menu's card and Settings → General: label of the chosen media player"))
                    Text(verbatim: model.chosenPlayerName ?? "AutoHush")
                        .font(.appHeadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: model.statusLine)
                        .font(.appSubheadline)
                        .foregroundStyle(model.statusNeedsAttention ? AnyShapeStyle(.appWarning) : AnyShapeStyle(.appSecondary))
                        .fixedSize(horizontal: false, vertical: true)
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
                ControlsRow(name: name, isLearned: model.learning?.isLearned == true) { model.learnControlsAgain() }
            }
            CardDivider()
            SwitchRow(
                Text("Auto-Pause", comment: "The switch that turns auto-pause on and off: its label in the menu's card and Settings → General, and a Diagnostics row"),
                subtitle: Text("Choose which apps pause your player on the Apps page.",
                               comment: "Settings → General, under the Auto-Pause switch; Apps is the Settings page that lists them"),
                isOn: Binding(get: { model.isAutoPauseOn }, set: { model.setAutoPause($0) })
            )
            if let note = model.autoPauseNote {
                Text(note).captionStyle()
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
        if model.chosenPlayer != nil {
            HStack(spacing: 12) {
                if let control = model.permissions.control, model.permissions.controlAccess.isSatisfied {
                    check(Self.allowedTitle(control), done: true)
                }
                if !model.playerCanFade {
                    check(String(localized: "No fades", comment: "Settings → General, under the media player: AutoHush can't fade this player (TIDAL, Apple Podcasts, web apps)"), done: false)
                } else if model.timings.fadesEnabled {
                    check(String(localized: "Fades", comment: "Settings: the page of playback's fade out and fade in (in the sidebar: keep it short, about 16 characters); also, with a check, under the media player in Settings → General, and a Diagnostics row: whether AutoHush can fade the media player"), done: true)
                } else {
                    check(String(localized: "Fades off", comment: "Settings → General, under the media player: fades are turned off on the Fades page"), done: false)
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
            String(localized: "Automation allowed", comment: "Settings → General, under the media player, with a check: AutoHush may control it through Automation")
        default:
            String(localized: "Accessibility allowed", comment: "Settings → General, under the media player, with a check: AutoHush may control it through Accessibility")
        }
    }
}
