import SwiftUI
import AutoHushKit

/// What the chosen player needs to be controlled and lacks, and the button
/// that allows it ("Allow … Access…", or "Open <player>" while Automation
/// waits for it to run): in Settings → General under the player, and in
/// Settings → Media Player above the players, in a card of its own (U7a,
/// the user's pick, 2026-11-02), with the same words in both. Nothing once
/// it's allowed.
struct ControlPermissionNote: View {
    let model: SettingsModel
    /// In a card of its own (Media Player's), not in one around it (General's).
    var ownCard = false

    var body: some View {
        let player = model.chosenPlayerName ?? ""
        // Its backup controls standing in, it's still controlled: said so (the user, 2026-11-05).
        if let control = model.permissions.control,
           let note = model.backupsStandIn.map({ Self.standInNote($0, player: player) })
                ?? Self.note(control, access: model.permissions.controlAccess, player: player) {
            if ownCard {
                Card { content(note, control) }
            } else {
                content(note, control)
            }
        }
    }

    @ViewBuilder private func content(_ note: String, _ control: Permission) -> some View {
        NoteLabel(note)
        PermissionButton(model: model, permission: control, access: model.permissions.controlAccess, long: true)
    }

    /// What it says of `player` while its control `permission` is missing
    /// and its backup controls stand in for it (`SettingsModel.backupsStandIn`);
    /// Fine-Tuning's player card says it too (`PlayerControlsCard`).
    static func standInNote(_ permission: Permission, player: String) -> String {
        if case .automation = permission {
            return String(localized: "Without Automation access, AutoHush controls \(player) by its backup controls.",
                          comment: "Settings → General under the media player, Settings → Media Player above the players, and Settings → Fine-Tuning's player card under “Use backup controls”: Automation isn't allowed, so AutoHush pauses and plays the player by its other ways (backup controls) meanwhile; %@ is the player")
        }
        return String(localized: "Without Accessibility access, AutoHush controls \(player) by its backup controls.",
                      comment: "Settings → General under the media player, Settings → Media Player above the players, and Settings → Fine-Tuning's player card under “Use backup controls”: Accessibility isn't allowed, so AutoHush pauses and plays the player by its other ways (backup controls) meanwhile; %@ is the player")
    }

    /// What it says of `player` while its control `permission` stands at
    /// `access`; `nil` once it's allowed or not needed: it doesn't show then.
    static func note(_ permission: Permission, access: PermissionAccess, player: String) -> String? {
        switch (permission, access) {
        case (_, .allowed), (_, .notNeeded):
            return nil
        case (_, .playerNotRunning):
            return PermissionText.controlNote(player, .playerNotRunning)
        case (.automation, _):
            return String(localized: "AutoHush can’t control \(player) without Automation access.",
                          comment: "Settings → General under the media player, and Settings → Media Player above the players, while Automation isn't allowed; %@ is the player")
        default:
            return String(localized: "AutoHush can’t control \(player) without Accessibility access.",
                          comment: "Settings → General under the media player, and Settings → Media Player above the players, while Accessibility isn't allowed; %@ is the player")
        }
    }
}
