import AppKit
import SwiftUI
import UniformTypeIdentifiers

// SwiftUI content of the Settings window's tabs.

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

struct AppsSettingsView: View {
    let model: SettingsModel
    @State private var confirmingReset = false

    var body: some View {
        Form {
            Section {
                if model.apps.isEmpty {
                    Text("Apps appear here once they have played audio.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.apps) { row in
                    Toggle(isOn: Binding(
                        get: { !row.isIgnored },
                        set: { model.setPausesMusic($0, for: row.source) }
                    )) {
                        Label {
                            Text(row.source.name)
                        } icon: {
                            Image(nsImage: AppIcon.image(for: row.source))
                        }
                    }
                    .contextMenu {
                        Button("Remove from List") { model.forget(row.source) }
                    }
                }
            } header: {
                Text("Pauses Music")
            } footer: {
                Text("Turn an app off to keep your music playing while it makes sound. Right-click an app to remove it from the list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Ignore Another App…") { chooseAppToIgnore() }
                    Spacer()
                    Button("Reset List…", role: .destructive) { confirmingReset = true }
                        .disabled(model.apps.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset the list of apps?", isPresented: $confirmingReset) {
            Button("Reset List", role: .destructive) { model.forgetAllApps() }
        } message: {
            Text("Every app is removed, and apps you turned off will pause your music again. Apps reappear as they play audio.")
        }
        .frame(width: 480, height: 420)
    }

    private func chooseAppToIgnore() {
        let panel = NSOpenPanel()
        panel.title = "Choose an App to Ignore"
        panel.prompt = "Ignore"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK,
              let url = panel.url,
              let source = ProcessAudioSourceIdentifier.source(forBundleAt: url)
        else { return }
        model.setPausesMusic(false, for: source)
    }
}

struct AdvancedSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                slider(
                    "Pause music after",
                    value: \.startConfirmation, range: TimingSettings.startConfirmationRange, step: 0.25,
                    format: seconds,
                    help: "How long another app must be audible. Filters out short sounds apps play themselves; system notification sounds are always ignored."
                )
                slider(
                    "Treat an app as stopped after",
                    value: \.stopGrace, range: TimingSettings.stopGraceRange, step: 0.5,
                    format: seconds,
                    help: "How long another app must be silent. Bridges gaps between tracks and videos."
                )
                slider(
                    "Resume music after",
                    value: \.resumeDelay, range: TimingSettings.resumeDelayRange, step: 0.25,
                    format: seconds,
                    help: "An extra delay once every other app has stopped."
                )
                slider(
                    "Silence threshold",
                    value: \.silenceThresholdDB, range: TimingSettings.silenceThresholdRange, step: 5,
                    format: { "\(Int($0)) dB" },
                    help: "Quieter output counts as silence. Only used while measuring audio levels (AntiDot mode off)."
                )
            }
            Section {
                Button("Restore Defaults") { model.restoreDefaultTimings() }
                    .disabled(model.timings == .defaults)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + " s"
    }

    private func slider(
        _ title: String,
        value keyPath: WritableKeyPath<TimingSettings, Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                Text(format(model.timings[keyPath: keyPath]))
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { model.timings[keyPath: keyPath] },
                    set: { newValue in
                        var timings = model.timings
                        timings[keyPath: keyPath] = newValue
                        model.setTimings(timings)
                    }
                ),
                in: range,
                step: step
            )
            Text(help)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// App icons for menus and Settings, cached by bundle path.
@MainActor
enum AppIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for source: AudioSource, size: CGFloat = 16) -> NSImage {
        let key = "\(source.bundlePath ?? "")#\(size)"
        if let cached = cache[key] { return cached }
        let image = (source.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSWorkspace.shared.icon(for: .application)).copy() as! NSImage
        image.size = NSSize(width: size, height: size)
        cache[key] = image
        return image
    }
}
