import SwiftUI
import AutoHushKit

/// Settings → General: launch at login, auto-pause, AntiDot mode and updates.
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
                HStack {
                    Button("Check Now") { model.checkForUpdates() }
                    if let status = model.updateStatus {
                        Text(status)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
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
