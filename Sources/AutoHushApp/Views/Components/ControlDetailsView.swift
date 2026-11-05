import SwiftUI
import AutoHushKit
import CheckedPlayers

/// The player's controls, the Details… sheet of Settings → Media Player
/// (the user, 2026-11-05): its main control, then its
/// backup controls in the order they're tried, each with how its check
/// found it (in every window state, not in some, not tried), the Play/Pause
/// key with when it's pressed. Done (Return) or Escape closes it.
struct ControlDetailsView: View {
    let player: String
    let controls: PlayerControls
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: player).font(.appHeadline).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(Text(verbatim: BackupText.mainControl)).accessibilityAddTraits(.isHeader)
                ControlRow(control: controls.main, player: player)
            }
            if !controls.backups.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(Text(verbatim: BackupText.backupControls)).accessibilityAddTraits(.isHeader)
                    if !controls.switches.usesBackups { Text(verbatim: BackupText.off).captionStyle() }
                    ForEach(Array(controls.backups.enumerated()), id: \.offset) { _, control in
                        ControlRow(control: control, player: player)
                    }
                }
                .opacity(controls.backupsInUse ? 1 : 0.6)
            }
            HStack {
                Spacer()
                MainButton(ButtonText.done, action: done)
            }
        }
        .padding(20)
        .frame(width: 440, alignment: .leading)
        .background {
            // Escape closes it too, as Cancel would: Done has Return.
            Button(ButtonText.done, action: done)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .focusable(false)
                .accessibilityHidden(true)
        }
    }
}

/// One control: a way its check tried, as Add an App's list shows it
/// (`WayRow`); the Play/Pause key, which no check tests, with when it's
/// pressed; a way kept before window states were (an older setup), by name.
private struct ControlRow: View {
    let control: PlayerControls.Control
    let player: String

    var body: some View {
        if let result = control.found {
            // A check with the app's windows closed tried only that state.
            WayRow(way: result, app: player, windowsClosed: result.states.contains { $0.state == .windowsClosed })
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WayRow.symbol(.notTried).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: WayText.control(control.kind))
                    if control.kind == .mediaKey { Text(verbatim: BackupText.keyNote(player)).captionStyle() }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
