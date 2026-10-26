import SwiftUI
import AutoHushKit

/// Settings → About's Updates (a page of their own until W1, the user,
/// 2026-10-25): the daily check, what it leads to as a pop-up menu (A4,
/// 2026-10-26; with a note while notifications are off), Check Now, and its
/// Restore Defaults.
struct UpdatesCard: View {
    let model: SettingsModel

    var body: some View {
        Card(Text(verbatim: UpdateOffer.updatesTitle)) {
            SwitchRow(Text("Check for updates automatically", comment: "Settings → About: switch for the daily update check"), isOn: Binding(
                get: { model.checksForUpdatesAutomatically },
                set: { model.updates.setChecksAutomatically($0) }
            ))
            // What checks lead to only matters while they run: greyed out otherwise.
            CardDivider()
            // A pop-up menu, as System Settings has them (A4, the user's pick,
            // 2026-10-26: chips were too much); what the choice does is its
            // help tag and VoiceOver hint.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    let title = String(localized: "When an update is found", comment: "Settings → About: lead-in to what happens when an update is found")
                    Text(verbatim: title) // a row's title
                    Spacer(minLength: 8)
                    Picker(selection: Binding(
                        // A copy that can't install itself can only notify.
                        get: { model.updateInstallNote == nil ? model.automaticUpdates : .notify },
                        set: { model.updates.setMode($0) }
                    )) {
                        ForEach(AutomaticUpdates.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                    } label: {
                        Text(verbatim: title)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(model.updateInstallNote != nil)
                    .help(model.automaticUpdates.explanation)
                    .accessibilityHint(Text(verbatim: model.automaticUpdates.explanation))
                }
                if let note = model.updateInstallNote { Text(note).captionStyle() }
            }
            // ← and → choose, while the arrow keys' highlight is on it.
            .highlightableRow(adjust: { step in
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
                RowTitle(Text(model.updateTitle), subtitle: model.lastCheckedNote().map { Text($0) })
                Spacer(minLength: 8)
                Button { model.updates.checkFromUser() } label: {
                    Text("Check Now", comment: "Settings → About: checks for an update now")
                }
                    .buttonStyle(.chip)
            }
            .highlightableRow(ownsControls: true, press: { model.updates.checkFromUser() })
        } footer: {
            RestoreDefaultsButton(isDefault: model.updatesAreDefaults) { model.restoreDefaultUpdates() }
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

/// Each update choice as Settings and Diagnostics show it.
extension AutomaticUpdates {
    var title: String {
        switch self {
        case .notify:
            return String(localized: "Notify me", comment: "Settings: an update choice")
        case .download:
            return String(localized: "Download it and notify me", comment: "Settings: an update choice")
        case .install:
            return String(localized: "Install it automatically", comment: "Settings: an update choice")
        }
    }

    /// What the choice means, under the choices.
    var explanation: String {
        switch self {
        case .notify:
            return String(localized: "AutoHush lets you know. Install the update from its menu whenever you like.",
                          comment: "Settings, under the update choice Notify me")
        case .download:
            return String(localized: "AutoHush downloads it and lets you know. It keeps the download for 7 days.",
                          comment: "Settings, under the update choice Download it and notify me")
        case .install:
            return String(localized: "AutoHush installs it when it isn’t holding your player paused, and lets you know afterwards.",
                          comment: "Settings, under the update choice Install it automatically")
        }
    }
}
