/// The Settings cards with a Restore Defaults (the user, 2026-10-25: one
/// for every card with settings): Behavior's switches, Fine-Tuning's
/// player controls (on Media Player until F4, 2026-11-05), sliders and
/// ways, General's Startup and Menu Bar, About's Updates.
/// `SettingsModel` says whether each is at its defaults and sets it back
/// (`isDefault(_:)`, `restoreDefaults(_:)`); Behavior's rows, and Media
/// Player's Controls row, open Fine-Tuning at one of its own
/// (`SettingsModel.fineTuningFocus`).
enum SettingsCard: Hashable, CaseIterable {
    // Behavior's
    case pausing, resuming, fades, volume, modes
    // Fine-Tuning's
    case playerControls, timing, fadeLengths, volumeLimits, detection
    // General's and About's
    case startup, updates

    /// The page that shows it: where its Restore Defaults is undone.
    var page: SettingsPage {
        switch self {
        case .pausing, .resuming, .fades, .volume, .modes: .behavior
        case .playerControls, .timing, .fadeLengths, .volumeLimits, .detection: .fineTuning
        case .startup: .general
        case .updates: .about
        }
    }
}
