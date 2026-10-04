import SwiftUI
import AutoHushKit

/// Settings → General: launch at login, auto-pause, AntiDot mode, updates
/// (and what automatic checks lead to), and a way to support AutoHush.
struct GeneralSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let error = model.launchAtLoginError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                    Button("Open Login Items Settings…") { model.openLoginItemsSettings() }
                }
            }

            Section {
                Toggle("Auto-Pause Music", isOn: Binding(
                    get: { model.isAutoPauseOn },
                    set: { model.setAutoPause($0) }
                ))
                if let note = model.autoPauseNote {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Choose which apps pause your music in the Apps tab.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("AntiDot mode", isOn: Binding(
                    get: { model.isAntiDotMode },
                    set: { model.setAntiDotMode($0) }
                ))
                Label {
                    Text("Hides the purple recording indicator by never measuring sound. Detection is less precise: some paused apps may keep your music paused.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.callout)
                if model.isAntiDotMode {
                    Picker("Detect playing apps by", selection: Binding(
                        get: { model.detectionMethod },
                        set: { model.setDetectionMethod($0) }
                    )) {
                        ForEach([DetectionMethod.playbackSignals, .openStreams], id: \.self) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    Text(model.detectionMethod.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { model.checksForUpdatesAutomatically },
                    set: { model.setChecksForUpdates($0) }
                ))
                VStack(alignment: .leading, spacing: 8) {
                    Text("When an update is found")
                    RadioChoices(
                        options: [AutomaticUpdates.notify, .download, .install].map {
                            .init(title: $0.title, value: $0, isAvailable: model.isAvailable($0))
                        },
                        // A copy that can't install itself can only notify.
                        selection: model.updateInstallNote == nil ? model.automaticUpdates : .notify,
                        onSelect: { model.setAutomaticUpdates($0) },
                        onUnavailableClick: { model.flashNotificationsNote() }
                    )
                    .disabled(!model.checksForUpdatesAutomatically || model.updateInstallNote != nil)
                }
                if let note = model.updateInstallNote {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if model.checksForUpdatesAutomatically {
                    Text(model.automaticUpdates.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                // Shown even with checks off: AutoHush turns them off when notifications go off.
                if model.notificationsOff {
                    // Blinks in white after a click on a choice that needs notifications.
                    Text("Notifications are off for AutoHush, so it can't tell you about updates.")
                        .font(.callout)
                        .foregroundStyle(model.notificationsNoteIsLit ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                    Button("Open Notifications Settings…") { model.openNotificationSettings() }
                }
                HStack {
                    Button("Check Now") { model.checkForUpdates() }
                    if let status = model.updateStatus {
                        Text(status)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                LabeledContent {
                    Link(destination: ProjectInfo.supportPage) {
                        Text("Buy me a coffee",
                             comment: "Link to the developer's Buy Me a Coffee page (About panel, Settings → General)")
                    }
                } label: {
                    Text("Would you like to support me?",
                         comment: "About panel and Settings → General, before the Buy me a coffee link")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The detection choices as Settings describes them.
private extension DetectionMethod {
    var title: String {
        switch self {
        case .audioLevels:
            return String(localized: "Measure audio levels", comment: "Settings: a way to detect playing apps")
        case .playbackSignals:
            return String(localized: "What apps tell macOS", comment: "Settings, AntiDot mode: a way to detect playing apps")
        case .openStreams:
            return String(localized: "Open audio streams only",
                          comment: "Settings, AntiDot mode: a way to detect playing apps")
        }
    }

    var summary: String {
        switch self {
        case .audioLevels:
            return String(localized: "Most accurate: a paused video stops counting as soon as it goes silent. macOS shows its purple recording indicator while AutoHush measures.")
        case .playbackSignals:
            return String(localized: "An app counts as playing while it tells macOS it is playing, and as paused once it stops, even with its audio still open. Apps that never tell macOS count while their audio is open.")
        case .openStreams:
            return String(localized: "Any app with its audio open counts as playing, even when paused.")
        }
    }
}

/// Each update choice as Settings shows it.
private extension AutomaticUpdates {
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
            return String(localized: "AutoHush installs it when it isn't holding your music paused, and lets you know afterwards.",
                          comment: "Settings, under the update choice Install it automatically")
        }
    }
}
