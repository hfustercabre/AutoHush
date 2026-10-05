import AppKit
import SwiftUI

/// Settings → Diagnostics: how AutoHush is doing, every app with its sound
/// on and how AutoHush judges it, then the music player, the detection, the
/// permissions, AutoHush and the Mac, kept up to date while shown. Each part
/// folds away under its heading, leaving a one-line summary; it scrolls, and
/// Copy Report stays below.
struct DiagnosticsSettingsView: View {
    let model: SettingsModel
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let diagnostics = model.diagnostics {
                        overview(diagnostics.overview)
                        part(.apps, title: DiagnosticsReport.appsTitle, symbol: "speaker.wave.2", summary: diagnostics.appsSummary) {
                            apps(diagnostics.apps)
                        }
                        ForEach(diagnostics.sections) { section in
                            part(.section(section.kind), title: section.title, symbol: symbol(for: section.kind),
                                 summary: section.summary) {
                                rows(section.rows)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .frame(height: 560)
            Divider()
            footer
        }
        .frame(width: 480)
        .onAppear { model.refreshDiagnostics() }
    }

    // MARK: - Parts

    /// How AutoHush is doing, at a glance.
    private func overview(_ overview: DiagnosticsSnapshot.Overview) -> some View {
        Card {
            HStack(spacing: 12) {
                Group {
                    switch overview.kind {
                    case .working:  Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    case .attention: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.appWarning)
                    case .off:      Image(systemName: "pause.circle.fill").foregroundStyle(.appSecondary)
                    case .starting: Image(systemName: "hourglass").foregroundStyle(.appSecondary)
                    }
                }
                .font(.system(size: 28))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: overview.title).font(.appHeadline)
                    Text(verbatim: overview.detail)
                        .foregroundStyle(.appSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// A heading that folds its part away; folded, it shows a summary.
    private func part(_ id: DiagnosticsSnapshot.Part, title: String, symbol: String, summary: String,
                      @ViewBuilder content: () -> some View) -> some View {
        let isOpen = !model.foldedDiagnostics.contains(id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if isOpen { model.foldedDiagnostics.insert(id) } else { model.foldedDiagnostics.remove(id) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: symbol)
                        .foregroundStyle(.tint)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(verbatim: title).font(.appHeadline)
                    Spacer(minLength: 8)
                    if !isOpen {
                        Text(verbatim: summary)
                            .font(.appCallout)
                            .foregroundStyle(.appSecondary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.appSecondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            if isOpen { content() }
        }
    }

    private func apps(_ apps: [DiagnosticsSnapshot.App]) -> some View {
        Card {
            if apps.isEmpty {
                Text(verbatim: DiagnosticsReport.noAudio).foregroundStyle(.appSecondary)
            }
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                if index > 0 { CardDivider() }
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
                            .foregroundStyle(.appSecondary)
                    }
                }
            }
        }
    }

    /// Each fact: its label on the left, its value on the right.
    private func rows(_ rows: [DiagnosticsSnapshot.Row]) -> some View {
        Card {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { CardDivider() }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: row.label).foregroundStyle(.appSecondary)
                    Spacer(minLength: 8)
                    if let mark = row.mark {
                        Group {
                            switch mark {
                            case .ok:      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            case .problem: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.appWarning)
                            case .neutral: Image(systemName: "minus.circle").foregroundStyle(.appSecondary)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    Text(verbatim: row.value)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func symbol(for kind: DiagnosticsSnapshot.Section.Kind) -> String {
        switch kind {
        case .player:      return "music.note"
        case .detection:   return "waveform"
        case .permissions: return "lock.shield"
        case .autoHush:    return "gearshape"
        case .mac:         return "laptopcomputer"
        }
    }

    // MARK: - Copy Report

    private var footer: some View {
        HStack {
            if copied {
                Label {
                    Text("Copied", comment: "Settings → Diagnostics: after Copy Report")
                } icon: {
                    Image(systemName: "checkmark")
                }
                .font(.appCallout)
                .foregroundStyle(.appSecondary)
            } else {
                Text("Updated as it happens.", comment: "Settings → Diagnostics, beside Copy Report")
                    .font(.appCallout)
                    .foregroundStyle(.appSecondary)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
