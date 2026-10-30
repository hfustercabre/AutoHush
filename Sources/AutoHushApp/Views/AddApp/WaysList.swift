import SwiftUI
import CheckedPlayers

/// The ways the check tried, each with how it did (C5).
struct WaysList: View {
    let result: CheckResult
    let app: String
    /// The panel's row shows no state: only its sound tells (in AntiDot
    /// mode, why nothing can be used).
    var panelNeedsSound = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(result.ways, id: \.kind) { way in
                WayRow(way: way, app: app, windowsClosed: result.windowsClosed, panelNeedsSound: panelNeedsSound)
            }
        }
    }
}

/// A way the check tried: its mark, its name (with a badge), and how it did.
struct WayRow: View {
    let way: CheckResult.WayResult
    let app: String
    /// The check found its windows closed (`CheckResult.windowsClosed`).
    var windowsClosed = false
    var recommended = false
    /// The panel's Now Playing row doesn't follow the app
    /// (`AddAppModel.panelNeedsSound`): if it's the panel that worked, only
    /// its sound tells.
    var panelNeedsSound = false
    /// Inside a choice card, whose button says it (`WayChoices.card`): not
    /// an element of its own, so "Works" is said once (2026-10-29).
    var inCard = false

    var body: some View {
        if inCard {
            row
        } else {
            // Its own label, not its texts combined: combined, a value of its
            // own would replace their words (STYLE_GUIDE, as checklist steps).
            // Its mark isn't read: a way that worked says so as its value, one
            // that worked in some window states too (its note says where not).
            row.accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: accessibilityWords))
                .accessibilityValue(Text(verbatim: accessibilityValue))
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Self.symbol(way.mark).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                // On their shared baseline: centered, the badge left the row's
                // baseline (which the mark follows) undecided, and macOS 14
                // crashed laying the window out again and again (2026-10-16).
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: WayText.title(way.kind)).fixedSize(horizontal: false, vertical: true)
                    if recommended { HeadingBadge(text: AddAppText.recommendedBadge, accent: true) }
                }
                // A way's exception (it works, but not in every window state)
                // as a warning: the orange triangle, the words in the primary
                // color (O3, the user's pick, 2026-10-27: W4's orange words read
                // at 1.7:1 on the chosen card in light mode), on every such way,
                // chosen or not (N3b, the user's pick, 2026-10-27: the recommended
                // one alone before).
                if way.mark == .some {
                    NoteLabel(AddAppText.wayNote(way, app: app, windowsClosed: windowsClosed), font: .appCaption)
                } else {
                    Text(verbatim: AddAppText.wayNote(way, app: app, windowsClosed: windowsClosed)).captionStyle()
                }
                if soundOnly {
                    Text(verbatim: AddAppText.panelSoundOnly).captionStyle()
                }
            }
        }
    }

    /// What VoiceOver reads of it: its name, its badge, its note and the
    /// panel's caption, as they show.
    var accessibilityWords: String {
        [WayText.title(way.kind), recommended ? AddAppText.recommendedBadge : nil,
         AddAppText.wayNote(way, app: app, windowsClosed: windowsClosed), soundOnly ? AddAppText.panelSoundOnly : nil]
            .compactMap { $0 }.joined(separator: "\n")
    }

    /// Its value: "Works" for a way that worked, else none.
    var accessibilityValue: String { way.worked ? AddAppText.wayWorks : "" }

    /// The panel that worked, its row showing no state: only its sound tells.
    private var soundOnly: Bool { way.kind == .panel && way.worked && panelNeedsSound }

    @ViewBuilder static func symbol(_ mark: CheckResult.Mark) -> some View {
        switch mark {
        case .works: Image(systemName: "checkmark.circle.fill").foregroundStyle(.appSuccess)
        case .some: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.appWarning)
        case .none, .notThere: Image(systemName: "xmark.circle.fill").foregroundStyle(.appSecondary)
        case .notTried, .notChecked, .noWindow, .noAutomation, .noAccessibility, .menuBarHidden, .toggleOnly:
            Image(systemName: "minus.circle").foregroundStyle(.appSecondary)
        }
    }
}
