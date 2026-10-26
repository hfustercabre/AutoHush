/// The Settings cards with a Restore Defaults (the user, 2026-10-25: one
/// for every card with settings): Behavior's switches, Fine-Tuning's
/// sliders and ways, General's Startup and Menu Bar, About's Updates.
/// `SettingsModel` says whether each is at its defaults and sets it back
/// (`isDefault(_:)`, `restoreDefaults(_:)`); Behavior's rows open
/// Fine-Tuning at one of its own (`SettingsModel.fineTuningFocus`).
enum SettingsCard: CaseIterable, Hashable {
    // Behavior's
    case pausing, resuming, fades, volume, modes
    // Fine-Tuning's
    case timing, fadeLengths, volumeLimits, detection
    // General's and About's
    case startup, updates
}
