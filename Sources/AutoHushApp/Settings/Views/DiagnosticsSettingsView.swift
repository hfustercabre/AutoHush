import AppKit
import SwiftUI

/// Settings → Diagnostics: every app with its sound on and how AutoHush
/// judges it, then AutoHush's own settings, kept up to date while shown;
/// Copy Report puts it all on the clipboard.
struct DiagnosticsSettingsView: View {
    let model: SettingsModel
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                if let apps = model.diagnostics?.apps, !apps.isEmpty {
                    ForEach(apps) { row(for: $0) }
                } else {
                    Text(verbatim: DiagnosticsReport.noAudio)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Apps with Sound", comment: "Settings → Diagnostics: heading of the apps that have their sound on")
            }

            Section {
                ForEach(model.diagnostics?.settings ?? [], id: \.self) { Text(verbatim: $0) }
            } header: {
                Text(verbatim: "AutoHush")
            }

            Section {
                HStack {
                    if copied {
                        Label {
                            Text("Copied", comment: "Settings → Diagnostics: after Copy Report")
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        copyReport()
                    } label: {
                        Text("Copy Report", comment: "Settings → Diagnostics: puts the report on the clipboard")
                    }
                    .disabled(model.diagnostics == nil)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refreshDiagnostics() }
    }

    private func row(for app: DiagnosticsSnapshot.App) -> some View {
        LabeledContent {
            if let evidence = app.evidence {
                Text(verbatim: evidence)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label {
                Text(verbatim: app.name)
                Text(verbatim: app.judgement)
            } icon: {
                Image(nsImage: AppIcon.image(bundlePath: app.bundlePath, size: 20))
            }
        }
    }

    private func copyReport() {
        guard let text = model.diagnostics?.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
