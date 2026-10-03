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
