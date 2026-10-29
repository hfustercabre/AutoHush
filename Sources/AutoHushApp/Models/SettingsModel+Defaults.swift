import AutoHushKit

/// Each card's Restore Defaults (the user, 2026-10-25: one for every card
/// with settings), shown only once something on it differs (RD1,
/// 2026-10-26): that card's settings only, what's greyed out left as it is.
extension SettingsModel {
    /// The card's settings are their defaults, or greyed out (Restore
    /// Defaults wouldn't change what shows, the workflow audit,
    /// 2026-10-22): its button has nothing to do.
    func isDefault(_ card: SettingsCard) -> Bool {
        restoredSettings(card) == currentSettings
    }

    /// Sets the card's settings back to their defaults, leaving what's
    /// greyed out as it is.
    func restoreDefaults(_ card: SettingsCard) {
        let restored = restoredSettings(card), current = currentSettings
        if restored.timings != current.timings { setTimings(restored.timings) }
        if restored.detectionMethod != current.detectionMethod { setDetectionMethod(restored.detectionMethod) }
        if restored.keepsMenuBarIconNearSystemIcons != current.keepsMenuBarIconNearSystemIcons {
            setKeepsMenuBarIconNearSystemIcons(restored.keepsMenuBarIconNearSystemIcons)
        }
        if restored.checksForUpdatesAutomatically != current.checksForUpdatesAutomatically {
            updates.setChecksAutomatically(restored.checksForUpdatesAutomatically)
        }
        if restored.automaticUpdates != current.automaticUpdates { updates.setMode(restored.automaticUpdates) }
    }

    /// The settings a card's Restore Defaults can change, as they are now.
    private var currentSettings: CardSettings {
        CardSettings(timings: timings, detectionMethod: detectionMethod,
                     keepsMenuBarIconNearSystemIcons: keepsMenuBarIconNearSystemIcons,
                     checksForUpdatesAutomatically: checksForUpdatesAutomatically,
                     automaticUpdates: automaticUpdates)
    }

    /// The settings as the card's Restore Defaults leaves them: its own back
    /// to their defaults, what's greyed out and the other cards' as they are.
    private func restoredSettings(_ card: SettingsCard) -> CardSettings {
        var restored = currentSettings
        switch card {
        // Pausing's: the microphone and an output going away off.
        case .pausing: restored.timings = timings.withDefaultPausing
        // Resuming's: Resume playback on, Stay paused after calls off.
        case .resuming: restored.timings = timings.withDefaultResuming
        // Fades': on, unless greyed out with a player AutoHush can't fade.
        case .fades:
            if playerCanFade { restored.timings = timings.withDefaultFades }
        // Volume's: Level the volume off, unless greyed out (AntiDot mode,
        // Resume playback off).
        case .volume:
            if !levelingUnavailable { restored.timings = timings.withDefaultVolume }
        // Modes': AntiDot mode off (its way, greyed out then, isn't
        // restored), or it can't be turned on with this player.
        case .modes:
            if isAntiDotMode { restored.detectionMethod = .audioLevels }
        // Timing's: 0.5 s, and 2 s unless greyed out with Resume playback off.
        case .timing:
            restored.timings.startConfirmation = TimingSettings.defaults.startConfirmation
            if timings.resumesPlayback { restored.timings.stopGrace = TimingSettings.defaults.stopGrace }
        // Fade Lengths': 1 s and 2 s, unless greyed out; the fade-in alone
        // while nothing resumes.
        case .fadeLengths:
            if !fadeLengthsUnavailable { restored.timings = timings.withDefaultFadeLengths(fadeIn: !fadeInUnused) }
        // Volume Limits': 10 and 2 dB, unless greyed out (leveling off or unavailable).
        case .volumeLimits:
            if !levelingLimitsUnavailable { restored.timings = timings.withDefaultVolumeLimits }
        // Detection's: in AntiDot mode its way, what apps tell macOS; out
        // of it, the silence threshold at −60 dB (each greyed out in the other).
        case .detection:
            if isAntiDotMode {
                restored.detectionMethod = .playbackSignals
            } else {
                restored.timings.silenceThresholdDB = TimingSettings.defaults.silenceThresholdDB
            }
        // Startup and Menu Bar's: the icon not kept beside the system's, as
        // on a fresh install (it stays where it is). Launch at login is the
        // user's Mac setup, not a tuning, so it's neither counted nor
        // restored (I1, the user, 2026-10-27: on for most people, it kept
        // the button showing, and the button turned it off).
        case .startup: restored.keepsMenuBarIconNearSystemIcons = false
        // Updates': checked daily and installed automatically, as on a fresh
        // install; the choice left alone while this copy can't install
        // updates (it's greyed out then).
        case .updates:
            restored.checksForUpdatesAutomatically = true
            if updateInstallNote == nil { restored.automaticUpdates = .install }
        }
        return restored
    }
}

/// The settings a card's Restore Defaults can change: the timings, the
/// detection, the menu bar icon's place and the updates' choices.
private struct CardSettings: Equatable {
    var timings: TimingSettings
    var detectionMethod: DetectionMethod
    var keepsMenuBarIconNearSystemIcons: Bool
    var checksForUpdatesAutomatically: Bool
    var automaticUpdates: AutomaticUpdates
}

private extension TimingSettings {
    /// These timings with Pausing's switches back to their defaults.
    var withDefaultPausing: TimingSettings {
        var timings = self
        timings.pausesForMicrophone = TimingSettings.defaults.pausesForMicrophone
        timings.pausesOnOutputDisconnect = TimingSettings.defaults.pausesOnOutputDisconnect
        return timings
    }

    /// These timings with Resuming's switches back to their defaults.
    var withDefaultResuming: TimingSettings {
        var timings = self
        timings.resumesPlayback = TimingSettings.defaults.resumesPlayback
        timings.staysPausedAfterCalls = TimingSettings.defaults.staysPausedAfterCalls
        return timings
    }

    /// These timings with the fades turned on again.
    var withDefaultFades: TimingSettings {
        var timings = self
        timings.fadesEnabled = TimingSettings.defaults.fadesEnabled
        return timings
    }

    /// These timings with Level the volume back to its default.
    var withDefaultVolume: TimingSettings {
        var timings = self
        timings.levelsMusic = TimingSettings.defaults.levelsMusic
        return timings
    }

    /// These timings with the fade lengths back to their defaults, the
    /// fade-in's only if `fadeIn`.
    func withDefaultFadeLengths(fadeIn: Bool) -> TimingSettings {
        var timings = self
        timings.fadeOutDuration = TimingSettings.defaults.fadeOutDuration
        if fadeIn { timings.fadeInDuration = TimingSettings.defaults.fadeInDuration }
        return timings
    }

    /// These timings with leveling's limits back to their defaults.
    var withDefaultVolumeLimits: TimingSettings {
        var timings = self
        timings.levelingMaxCutDB = TimingSettings.defaults.levelingMaxCutDB
        timings.levelingMinCutDB = TimingSettings.defaults.levelingMinCutDB
        return timings
    }
}
