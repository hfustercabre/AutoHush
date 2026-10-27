import SwiftUI
import AutoHushKit

/// Settings → About's Updates (a page of their own until W1, the user,
/// 2026-10-25): the daily check, what it leads to as a pop-up menu (A4,
/// 2026-10-26; with a note while notifications are off), Check Now, and its
/// Restore Defaults.
struct UpdatesCard: View {
    let model: SettingsModel
    /// Opens the update pop-up from the keys.
    @State private var popUp = PopUpOpener()

    var body: some View {
        Card(Text(verbatim: UpdateOffer.updatesTitle)) {
            SwitchRow(Text("Check for updates automatically", comment: "Settings → About: switch for the daily update check"), isOn: Binding(
                get: { model.checksForUpdatesAutomatically },
                set: { model.updates.setChecksAutomatically($0) }
            ))
            // What checks lead to only matters while they run: greyed out otherwise.
            CardDivider()
            // A pop-up menu, as System Settings has them (A4, the user's pick,
            // 2026-10-26: chips were too much), borderless as every pop-up
            // (U3, the user, 2026-10-27); what the choice does is its help
            // tag and VoiceOver hint.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    let title = String(localized: "When an update is found", comment: "Settings → About: lead-in to what happens when an update is found")
                    // The pop-up, its help tag and its hint all say the choice shown.
                    let shown = model.shownAutomaticUpdates
                    Text(verbatim: title) // a row's title
                        .accessibilityHidden(true) // the pop-up says it, as its label
                    Spacer(minLength: 8)
                    Picker(selection: Binding(
                        get: { model.shownAutomaticUpdates },
                        set: { model.updates.setMode($0) }
                    )) {
                        ForEach(AutomaticUpdates.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                    } label: {
                        Text(verbatim: title)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .opened(by: popUp)
                    .disabled(model.updateInstallNote != nil)
                    .help(shown.explanation)
                    .accessibilityHint(Text(verbatim: shown.explanation))
                }
                if let note = model.updateInstallNote { Text(note).captionStyle() }
            }
            // ← and → choose, while the arrow keys' highlight is on it;
            // Return or Space shows the choices (`PopUpOpener`).
            .highlightableRow(press: {
                guard model.updateInstallNote == nil else { return }
                popUp.open()
            }, adjust: { step in
                guard model.updateInstallNote == nil,
                      let mode = AutomaticUpdates.allCases.stepping(from: model.automaticUpdates, by: step) else { return }
                model.updates.setMode(mode)
            })
            .unavailable(!model.checksForUpdatesAutomatically)
            if !model.checksForUpdatesAutomatically {
                NoteLabel(SettingsSwitch.updateChecksOffNote, kind: .info)
            } else {
                // Every choice still works: the menu bar icon says what a notification would.
                if model.notificationsOff {
                    Text(verbatim: Self.notificationsOffNote).captionStyle()
                    Button { model.actions?.openNotificationSettings() } label: {
                        Text("Open Notifications Settings…", comment: "Settings → About: button that opens System Settings → Notifications")
                    }
                        .buttonStyle(.chip)
                }
            }
            CardDivider()
            HStack {
                let row = model.updateRow()
                RowTitle(Text(row.title), subtitle: row.subtitle.map { Text($0) })
                Spacer(minLength: 8)
                Button { model.updates.checkFromUser() } label: {
                    Text("Check Now", comment: "Settings → About: checks for an update now")
                }
                    .buttonStyle(.chip)
            }
            .highlightableRow(ownsControls: true, press: { model.updates.checkFromUser() })
        } footer: {
            RestoreDefaultsButton(model: model, card: .updates)
        }
    }
}

extension UpdatesCard {
    /// Under the update choices while notifications are off.
    private static var notificationsOffNote: String {
        String(localized: "Notifications are off for AutoHush: its menu bar icon shows when an update is found.",
               comment: "Settings → About, under the update choices, while notifications are off for AutoHush")
    }
}
