import AutoHushKit
import Foundation

/// Settings → Diagnostics, as it is now.
struct DiagnosticsSnapshot: Equatable {
    /// How AutoHush is doing, at the top.
    struct Overview: Equatable {
        enum Kind: Equatable { case working, attention, off, starting }
        let kind: Kind
        let title: String
        let detail: String
    }

    /// An app with its sound on.
    struct App: Equatable, Identifiable {
        let id: String
        let name: String
        let bundlePath: String?
        /// How AutoHush judges it, e.g. "Playing, ignored".
        let judgement: String
        /// What the judgement rests on, e.g. "-20 dBFS".
        let evidence: String?
    }

    /// A label and its value, with a mark for permissions and problems,
    /// and a problem's fix, where AutoHush has one (the user's pick, the
    /// workflow audit, 2026-10-22).
    struct Row: Equatable {
        enum Mark: Equatable { case ok, problem, neutral }
        /// What its button does: choose a player (Settings → General), learn
        /// the web app's controls, or allow a permission.
        enum Fix: Equatable {
            case choosePlayer, learnControls
            case allow(Permission)
        }
        let label: String
        let value: String
        var mark: Mark?
        var fix: Fix?
    }

    /// A section below the apps; folded, it shows `summary`.
    struct Section: Equatable, Identifiable {
        enum Kind: Hashable { case player, behavior, detection, permissions, autoHush, mac }
        let kind: Kind
        let title: String
        let summary: String
        let rows: [Row]
        var id: Kind { kind }
    }

    /// A part that folds away under its heading: the apps, or a section.
    enum Part: Hashable {
        case apps
        case section(Section.Kind)
    }

    let overview: Overview
    let apps: [App]
    /// The apps' names, shown while their section is folded.
    let appsSummary: String
    let sections: [Section]
    /// The whole report, for Copy Report.
    let text: String
}
