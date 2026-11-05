/// The Settings cards with a Restore Defaults (the user, 2026-10-25: one
/// for every card with settings): Behavior's switches, Fine-Tuning's
/// sliders and ways, General's Startup and Menu Bar, Media Player's
/// backup controls (2026-11-05), About's Updates.
/// `SettingsModel` says whether each is at its defaults and sets it back
/// (`isDefault(_:)`, `restoreDefaults(_:)`); Behavior's rows open
/// Fine-Tuning at one of its own (`SettingsModel.fineTuningFocus`).
enum SettingsCard: Hashable, CaseIterable {
    // Behavior's
    case pausing, resuming, fades, volume, modes
    // Fine-Tuning's
    case timing, fadeLengths, volumeLimits, detection
    // General's, Media Player's and About's
    case startup, playerControls, updates

    /// The page that shows it: where its Restore Defaults is undone.
    var page: SettingsPage {
        switch self {
        case .pausing, .resuming, .fades, .volume, .modes: .behavior
        case .timing, .fadeLengths, .volumeLimits, .detection: .fineTuning
        case .startup: .general
        case .playerControls: .mediaPlayer
        case .updates: .about
        }
    }
}
