import AutoHushKit

/// The settings a card's Restore Defaults can change: the timings, the
/// detection, the menu bar icon's place, the chosen player's main control
/// and backup switches, and the updates' choices. It sets them through these alone, so
/// they're also all its Undo needs to keep.
struct CardSettings: Equatable {
    var timings: TimingSettings
    var detectionMethod: DetectionMethod
    var keepsMenuBarIconNearSystemIcons: Bool
    var checksForUpdatesAutomatically: Bool
    var automaticUpdates: AutomaticUpdates
    var getsReleaseCandidates: Bool
    var backupSwitches: ChosenBackupSwitches?

    /// These settings with each one that differs between `old` and `new`
    /// set as in `new`, timing by timing: what a restore (or its Undo)
    /// changed, the rest as it is here. A setting missing below would be
    /// left out of Undo; SettingsModelUndoTests restores every card.
    func changing(from old: CardSettings, to new: CardSettings) -> CardSettings {
        var settings = self
        func take<Value: Equatable>(_ path: WritableKeyPath<CardSettings, Value>) {
            if old[keyPath: path] != new[keyPath: path] { settings[keyPath: path] = new[keyPath: path] }
        }
        take(\.timings.startConfirmation)
        take(\.timings.stopGrace)
        take(\.timings.silenceThresholdDB)
        take(\.timings.fadeOutDuration)
        take(\.timings.fadeInDuration)
        take(\.timings.fadesEnabled)
        take(\.timings.levelsMusic)
        take(\.timings.levelingMaxCutDB)
        take(\.timings.levelingMinCutDB)
        take(\.timings.pausesOnOutputDisconnect)
        take(\.timings.resumesPlayback)
        take(\.timings.pausesForMicrophone)
        take(\.timings.staysPausedAfterCalls)
        take(\.timings.pausesForVoiceOver)
        take(\.detectionMethod)
        take(\.keepsMenuBarIconNearSystemIcons)
        take(\.checksForUpdatesAutomatically)
        take(\.automaticUpdates)
        take(\.getsReleaseCandidates)
        // Field by field (the main control, each switch), and only for the
        // player they were the settings of.
        if var now = settings.backupSwitches, old.backupSwitches?.bundleID == now.bundleID, new.backupSwitches?.bundleID == now.bundleID,
           let before = old.backupSwitches?.switches, let after = new.backupSwitches?.switches {
            if before.mainControl != after.mainControl { now.switches.mainControl = after.mainControl }
            if before.usesBackups != after.usesBackups { now.switches.usesBackups = after.usesBackups }
            if before.panelWhileMuted != after.panelWhileMuted { now.switches.panelWhileMuted = after.panelWhileMuted }
            settings.backupSwitches = now
        }
        return settings
    }
}
