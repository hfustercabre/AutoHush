import AppKit
import SwiftUI

/// Settings → Diagnostics: how AutoHush is doing, every app with its sound
/// on and how AutoHush judges it, then the media player, the detection, the
/// permissions, AutoHush and the Mac, kept up to date while shown, as
/// macOS's grouped form. Each part folds away under its heading, leaving a
/// one-line summary; the form scrolls, and Copy Report stays at the
/// window's foot.
struct DiagnosticsSettingsView: View {
    let model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
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
            .formStyle(.grouped)
            .environment(\.cardsAreFormSections, true)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.actions?.refreshDiagnostics() }
    }

    // MARK: - Parts

    /// How AutoHush is doing, at a glance.
    private func overview(_ overview: DiagnosticsSnapshot.Overview) -> some View {
        // At the top, not beside the buttons at its foot: there it left them
        // too little room in several languages.
        Card(note: Text("Updated as it happens.", comment: "Settings → Diagnostics, at the top of the page: what it shows is kept up to date")) {
            HStack(spacing: 12) {
                Group {
                    switch overview.kind {
                    case .working:  Image(systemName: "checkmark.seal.fill").foregroundStyle(.appSuccess)
                    case .attention: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.appWarning)
                    case .off:      Image(systemName: "pause.circle.fill").foregroundStyle(.appSecondary)
                    case .starting: Image(systemName: "hourglass").foregroundStyle(.appSecondary)
                    }
                }
                .font(.largeTitle)
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
        let toggle = { if model.foldedDiagnostics.remove(id) == nil { model.foldedDiagnostics.insert(id) } }
        // A section of the form, its folding title over it.
        return Card(heading: AnyView(Button(action: toggle) {
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
                    // Points forward while folded and down while open, whichever
                    // way the language reads: right to left, SwiftUI mirrors
                    // both the symbol and the turn.
                    Image(systemName: "chevron.forward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.appSecondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 4) // in line with the other sections' titles
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(HighlightableControl(cornerRadius: 6, press: toggle))
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isOpen ? AccessibilityText.expanded : AccessibilityText.collapsed))) {
            if isOpen { content() }
        }
    }

    private func apps(_ apps: [DiagnosticsSnapshot.App]) -> some View {
        Group {
            if apps.isEmpty {
                Text(verbatim: DiagnosticsReport.noAudio).foregroundStyle(.appSecondary)
            }
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                if index > 0 { CardDivider() }
                HStack(spacing: 8) {
                    Image(nsImage: AppIcon.image(bundlePath: app.bundlePath, id: app.id, players: model.playerOptions, size: 24))
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
        Group {
            // By label: a row that comes or goes leaves the others be.
            ForEach(rows.keyed(by: \.label)) { keyed in
                let row = keyed.element
                if keyed.offset > 0 { CardDivider() }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: row.label).foregroundStyle(.appSecondary)
                    Spacer(minLength: 8)
                    if let mark = row.mark {
                        Group {
                            switch mark {
                            case .ok:      Image(systemName: "checkmark.circle.fill").foregroundStyle(.appSuccess)
                            case .problem: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.appWarning)
                            case .neutral: Image(systemName: "minus.circle").foregroundStyle(.appSecondary)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    Text(verbatim: row.value)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                    if let fix = row.fix {
                        Button { perform(fix) } label: { Text(verbatim: Self.title(of: fix)) }
                            .buttonStyle(.chip)
                            .fixedSize()
                    }
                }
            }
        }
    }

    /// A problem's fix, as the same button does elsewhere: Settings →
    /// General's players, the card's Learn Controls…, a permission's Allow….
    private func perform(_ fix: DiagnosticsSnapshot.Row.Fix) {
        switch fix {
        case .choosePlayer: model.actions?.openSettings(page: .mediaPlayer)
        case .learnControls: model.actions?.learnControlsAgain()
        case .allow(let permission): model.actions?.requestPermission(permission)
        }
    }

    static func title(of fix: DiagnosticsSnapshot.Row.Fix) -> String {
        switch fix {
        case .choosePlayer: ChooseText.choose
        case .learnControls: LearningText.learnButton
        case .allow: ButtonText.allow
        }
    }

    private func symbol(for kind: DiagnosticsSnapshot.Section.Kind) -> String {
        switch kind {
        case .player:      return "music.note"
        case .behavior:    return "playpause"
        case .detection:   return "waveform"
        case .permissions: return "lock.shield"
        case .autoHush:    return "gearshape"
        case .mac:         return "laptopcomputer"
        }
    }

    // MARK: - Copy Report

    private var footer: some View {
        BottomBar {
            Spacer()
            Button { model.actions?.showLogs() } label: {
                Text("Show Logs…", comment: "Settings → Diagnostics: button at its foot that opens the window with AutoHush's logs")
            }
            .buttonStyle(.chip)
            // "Copied" for a moment after a click, as the logs window's Copy Logs.
            CopyButton(title: Text("Copy Report", comment: "Settings → Diagnostics: puts the report on the clipboard")) {
                model.diagnostics?.text
            }
            .disabled(model.diagnostics == nil)
        }
    }
}
