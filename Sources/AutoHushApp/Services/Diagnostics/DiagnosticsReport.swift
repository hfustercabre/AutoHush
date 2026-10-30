import Foundation
import AutoHushKit
import CheckedPlayers

/// What Settings → Diagnostics shows: how AutoHush is doing, every app with
/// its sound on and how AutoHush judges it, then a section each for the
/// media player, the detection, the permissions, AutoHush and the Mac; and
/// all of it as text, for Copy Report. The sections are in `+Sections`,
/// the words they use in `+Words`.
enum DiagnosticsReport {
    /// `bundlePath` finds an app's bundle, for its icon; `ways`, the ways an
    /// app added with Add an App is controlled by (its player's setup).
    static func snapshot(
        activeAudio: [ActiveAudioReport.Entry],
        status: AppStatus,
        facts: DiagnosticsFacts,
        bundlePath: (String) -> String? = { _ in nil },
        ways: (String) -> [PlayerSetup.Way]? = { _ in nil }
    ) -> DiagnosticsSnapshot {
        let apps = activeAudio.map { entry in
            DiagnosticsSnapshot.App(
                id: entry.id,
                name: entry.name ?? entry.id,
                bundlePath: bundlePath(entry.id),
                judgement: sentenceCase(describe(entry.state, isIgnored: entry.isIgnored)),
                evidence: entry.evidence.map(describe)
            )
        }
        let overview = overview(status: status)
        let sections = sections(status: status, facts: facts, ways: ways)
        let appsSummary = apps.isEmpty
            ? NoneText.title
            : apps.map(\.name).formatted(.list(type: .and, width: .narrow))
        return DiagnosticsSnapshot(
            overview: overview,
            apps: apps,
            appsSummary: appsSummary,
            sections: sections,
            text: text(overview: overview, activeAudio: activeAudio, sections: sections)
        )
    }

    /// Said when no app has its sound on.
    static var noAudio: String {
        String(localized: "No other app is playing sound right now.", comment: "Diagnostics")
    }

    static var appsTitle: String {
        String(localized: "Apps with Sound", comment: "Settings → Diagnostics: heading of the apps that have their sound on")
    }

    // MARK: - How AutoHush is doing

    private static func overview(status: AppStatus) -> DiagnosticsSnapshot.Overview {
        // Ready, but the player's state not known yet: still starting.
        if status.health == .starting || status.isReady && status.playback == .unknown {
            return .init(kind: .starting,
                         title: String(localized: "Starting…", comment: "Diagnostics: AutoHush is starting"),
                         detail: status.statusLine)
        }
        if status.needsAttention {
            return .init(kind: .attention,
                         title: String(localized: "Needs your attention", comment: "Diagnostics: something keeps AutoHush from working"),
                         detail: status.statusLine)
        }
        if status.autoPause != .on {
            return .init(kind: .off, title: status.statusLine,
                         detail: String(localized: "Turn Auto-Pause back on in the menu or in Settings.",
                                        comment: "Diagnostics, while auto-pause is off"))
        }
        return .init(kind: .working,
                     title: String(localized: "Working normally", comment: "Diagnostics: AutoHush is working"),
                     detail: "\(status.cardTitle) · \(status.statusLine)")
    }

    // MARK: - Text, for Copy Report

    private static func text(overview: DiagnosticsSnapshot.Overview, activeAudio: [ActiveAudioReport.Entry],
                             sections: [DiagnosticsSnapshot.Section]) -> String {
        let apps = activeAudio.isEmpty ? noAudio : activeAudio.map(line(for:)).joined(separator: "\n")
        let blocks = ["\(overview.title) — \(overview.detail)", "\(appsTitle)\n\(apps)"]
            + sections.map { section in
                ([section.title] + section.rows.map { "\($0.label): \($0.value)" }).joined(separator: "\n")
            }
        return blocks.joined(separator: "\n\n")
    }

    /// One app's line, e.g. "Google Chrome (com.google.Chrome) — playing (-23 dBFS)".
    static func line(for entry: ActiveAudioReport.Entry) -> String {
        let app = entry.name.map {
            String(localized: "\($0) (\(entry.id))", comment: "Diagnostics: an app's name, then its bundle ID")
        } ?? entry.id
        let state = describe(entry.state, isIgnored: entry.isIgnored)
        guard let evidence = entry.evidence.map(describe) else {
            return String(localized: "\(app) — \(state)", comment: "Diagnostics: an app, then how AutoHush judges it")
        }
        return String(localized: "\(app) — \(state) (\(evidence))",
                      comment: "Diagnostics: an app, how AutoHush judges it, and what that rests on")
    }
}
