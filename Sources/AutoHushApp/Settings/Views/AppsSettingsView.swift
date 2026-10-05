import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AutoHushKit

/// Settings → Apps: which apps pause the music, in a card like the menu's
/// "Playing now", each with its switch.
struct AppsSettingsView: View {
    let model: SettingsModel
    @State private var confirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(Text("Pauses Music"))
                        .padding(.leading, 4)
                    Card {
                        if model.apps.isEmpty {
                            Text("Apps appear here once they have played audio.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(model.apps.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { CardDivider() }
                            appRow(row)
                        }
                    }
                    Text("Turn an app off to keep your music playing while it makes sound. Right-click an app to remove it from the list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            HStack {
                Button("Ignore Another App…") { chooseAppToIgnore() }
                    .buttonStyle(.chip)
                Spacer()
                Button("Reset List…", role: .destructive) { confirmingReset = true }
                    .buttonStyle(.chip)
                    .disabled(model.apps.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .confirmationDialog("Reset the list of apps?", isPresented: $confirmingReset) {
            Button("Reset List", role: .destructive) { model.forgetAllApps() }
        } message: {
            Text("Every app is removed, and apps you turned off will pause your music again. Apps reappear as they play audio.")
        }
        .frame(width: 480, height: 440)
    }

    /// The app's icon and name, whether it pauses the music, and its switch.
    private func appRow(_ row: SettingsModel.AppRow) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIcon.image(for: row.source, size: 24))
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            RowTitle(
                Text(verbatim: row.source.name),
                subtitle: row.isIgnored ? Text("Ignored — music keeps playing") : Text("Pauses your music")
            )
            Spacer(minLength: 8)
            Toggle(isOn: Binding(
                get: { !row.isIgnored },
                set: { model.setPausesMusic($0, for: row.source) }
            )) {
                Text(verbatim: row.source.name)
            }
            .toggleStyle(PillToggleStyle(width: 30, height: 18))
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove from List") { model.forget(row.source) }
        }
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
