import AppKit
import SwiftUI

/// Settings → Diagnostics, in cards like the menu's: every app with its
/// sound on and how AutoHush judges it, then AutoHush's own settings, kept up
/// to date while shown; Copy Report puts it all on the clipboard.
struct DiagnosticsSettingsView: View {
    let model: SettingsModel
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(Text("Apps with Sound", comment: "Settings → Diagnostics: heading of the apps that have their sound on"))
            Card {
                if let apps = model.diagnostics?.apps, !apps.isEmpty {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        if index > 0 { CardDivider() }
                        row(for: app)
                    }
                } else {
                    Text(verbatim: DiagnosticsReport.noAudio)
                        .foregroundStyle(.secondary)
                }
            }

            heading(Text(verbatim: "AutoHush"))
            Card {
                ForEach(Array((model.diagnostics?.settings ?? []).enumerated()), id: \.offset) { index, line in
                    if index > 0 { CardDivider() }
                    Text(verbatim: line)
                }
            }

            HStack {
                if copied {
                    Label {
                        Text("Copied", comment: "Settings → Diagnostics: after Copy Report")
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    copyReport()
                } label: {
                    Text("Copy Report", comment: "Settings → Diagnostics: puts the report on the clipboard")
                }
                .buttonStyle(.chip)
                .disabled(model.diagnostics == nil)
            }
            .padding(.top, 6)
        }
        .padding(16)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refreshDiagnostics() }
    }

    private func heading(_ title: Text) -> some View {
        SectionLabel(title)
            .padding(.leading, 4)
            .padding(.top, 6)
    }

    private func row(for app: DiagnosticsSnapshot.App) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: AppIcon.image(bundlePath: app.bundlePath, size: 24))
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            RowTitle(Text(verbatim: app.name), subtitle: Text(verbatim: app.judgement))
            Spacer(minLength: 8)
            if let evidence = app.evidence {
                Text(verbatim: evidence)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
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
