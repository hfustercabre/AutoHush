import Foundation

/// The Settings window's pages, in the sidebar's order.
enum SettingsPage: CaseIterable, Hashable {
    case general, mediaPlayer, soundSources, behavior, fineTuning, diagnostics, about

    /// The sidebar's groups of pages, a gap between each (B, the user's
    /// pick, 2026-10-21; W1, W2 and W3, 2026-10-25; memory
    /// `settings-layout`): since S5d + S5a (the user's pick, 2026-10-25)
    /// Everyday's pages and Advanced's, each named with what it's for,
    /// then About.
    static let groups: [Group] = [
        Group(title: Group.everydayTitle, note: Group.everydayNote, pages: [.general, .mediaPlayer, .soundSources, .behavior]),
        Group(title: Group.advancedTitle, note: Group.advancedNote, pages: [.fineTuning, .diagnostics]),
        Group(title: nil, note: nil, pages: [.about]),
    ]

    /// A group of the sidebar's pages, under its name and what it's for.
    struct Group {
        let title: String?
        let note: String?
        let pages: [SettingsPage]

        static var everydayTitle: String {
            String(localized: "Everyday", comment: "Settings' sidebar: the name over the pages most people use (General, Media Player, Sound Sources, Behavior)")
        }

        static var everydayNote: String {
            String(localized: "What most people change", comment: "Settings' sidebar, under “Everyday”: what its pages are for")
        }

        static var advancedTitle: String {
            String(localized: "Advanced", comment: "Settings' sidebar: the name over Fine-Tuning and Diagnostics, for people who want to adjust more or look closer")
        }

        static var advancedNote: String {
            String(localized: "Fine-tuning and checks", comment: "Settings' sidebar, under “Advanced”: what its pages are for (Fine-Tuning's settings, Diagnostics' checks)")
        }
    }

    var title: String {
        switch self {
        case .general:
            String(localized: "General", comment: "Settings: a page in the sidebar")
        case .mediaPlayer:
            PlayerOption.mediaPlayerHeading
        case .soundSources:
            String(localized: "Sound Sources", comment: "Settings: a page in the sidebar: the apps heard playing sound, each switched to pause your player or be ignored (keep it short, about 16 characters)")
        case .behavior:
            String(localized: "Behavior", comment: "Settings: a page in the sidebar: the switches for when your player pauses and resumes, the fades, the volume and AntiDot mode (keep it short, about 16 characters)")
        case .fineTuning:
            String(localized: "Fine-Tuning", comment: "Settings: a page in the sidebar, under Advanced: the timings, fade lengths, volume limits and detection that Behavior's switches use (keep it short, about 16 characters)")
        case .diagnostics:
            String(localized: "Diagnostics", comment: "Settings: a page in the sidebar: what AutoHush sees right now")
        case .about:
            String(localized: "About", comment: "Menu: button at the bottom; shows About AutoHush")
        }
    }

    /// The page's symbol in the sidebar, on a square tinted with the
    /// accent color.
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .mediaPlayer: "music.note"
        case .soundSources: "square.grid.2x2.fill"
        case .behavior: "playpause.fill"
        case .fineTuning: "slider.horizontal.3"
        case .diagnostics: "stethoscope"
        case .about: "info.circle.fill"
        }
    }
}
