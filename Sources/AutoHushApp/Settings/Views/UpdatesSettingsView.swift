import SwiftUI
import AutoHushKit

/// Settings → Updates, in a card like the menu's: the daily check, what it
/// leads to, a note while notifications are off, and Check Now.
struct UpdatesSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            Card {
                SwitchRow(Text("Check for updates automatically", comment: "Settings → Updates: switch for the daily update check"), isOn: Binding(
                    get: { model.checksForUpdatesAutomatically },
                    set: { model.setChecksForUpdates($0) }
                ))
                // What checks lead to only matters while they run.
                if model.checksForUpdatesAutomatically {
                    CardDivider()
                    SectionLabel(Text("When an update is found", comment: "Settings → Updates: lead-in to what happens when an update is found"))
                    ChoiceChips(
                        options: [AutomaticUpdates.notify, .download, .install].map {
                            .init(title: $0.title, value: $0, isAvailable: model.isAvailable($0))
                        },
                        // A copy that can't install itself can only notify.
                        selection: model.updateInstallNote == nil ? model.automaticUpdates : .notify,
                        onSelect: { model.setAutomaticUpdates($0) },
                        onUnavailableClick: { model.flashNotificationsNote() }
                    )
                    .disabled(model.updateInstallNote != nil)
                    Text(model.updateInstallNote ?? model.automaticUpdates.explanation).captionStyle()
                }
                // Shown even with checks off: AutoHush turns them off when notifications go off.
                if model.notificationsOff {
                    // Blinks bright after a click on a choice that needs notifications.
                    Text("Notifications are off for AutoHush, so it can't tell you about updates.",
                         comment: "Settings → Updates, under the update choices, while notifications are off for AutoHush")
                        .font(.appCaption)
                        .foregroundStyle(model.notificationsNoteIsLit ? AnyShapeStyle(.primary) : AnyShapeStyle(.appSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                    Button { model.openNotificationSettings() } label: {
                        Text("Open Notifications Settings…", comment: "Settings → Updates: button that opens System Settings → Notifications")
                    }
                        .buttonStyle(.chip)
                }
                CardDivider()
                HStack {
                    RowTitle(Text(model.updateTitle), subtitle: model.lastCheckedNote().map { Text($0) })
                    Spacer(minLength: 8)
                    Button { model.checkForUpdates() } label: {
                        Text("Check Now", comment: "Settings → Updates: checks for an update now")
                    }
                        .buttonStyle(.chip)
                }
            }
        }
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
            return String(localized: "AutoHush installs it when it isn't holding your player paused, and lets you know afterwards.",
                          comment: "Settings, under the update choice Install it automatically")
        }
    }
}
