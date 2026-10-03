import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AutoHushKit

/// Settings → Apps: which apps pause the music.
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
        panel.title = String(localized: "Choose an App to Ignore", comment: "Title of the panel that picks an app")
        panel.prompt = String(localized: "Ignore", comment: "Button of the panel that picks an app to ignore")
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK,
              let url = panel.url,
              let source = ProcessAudioSourceIdentifier.source(forBundleAt: url)
        else { return }
        model.setPausesMusic(false, for: source)
    }
}
