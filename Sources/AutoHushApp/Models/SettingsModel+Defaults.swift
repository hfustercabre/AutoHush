import AutoHushKit

/// Each card's Restore Defaults (the user, 2026-10-25: one for every card
/// with settings), shown only once something on it differs (RD1,
/// 2026-10-26): that card's settings only, what's greyed out left as it is.
extension SettingsModel {
    /// The card's settings are their defaults, or greyed out (Restore
    /// Defaults wouldn't change what shows, the workflow audit,
    /// 2026-10-22): its button has nothing to do.
    func isDefault(_ card: SettingsCard) -> Bool {
        switch card {
        // Pausing's: the microphone and an output going away off.
        case .pausing: timings.withDefaultPausing == timings
        // Resuming's: Resume playback on, Stay paused after calls off.
        case .resuming: timings.withDefaultResuming == timings
        // Fades': on, or greyed out with a player AutoHush can't fade.
        case .fades: !playerCanFade || timings.withDefaultFades == timings
        // Volume's: Level the volume off, or greyed out (AntiDot mode,
        // Resume playback off).
        case .volume: SettingsSwitch.levelsMusic.isUnavailable(self) || timings.withDefaultVolume == timings
        // Modes': AntiDot mode off (its way, greyed out then, isn't
        // restored), or it can't be turned on with this player.
        case .modes: !isAntiDotMode
        // Timing's: 0.5 s, and 2 s unless greyed out with Resume playback off.
        case .timing:
            timings.startConfirmation == TimingSettings.defaults.startConfirmation
                && (!timings.resumesPlayback || timings.stopGrace == TimingSettings.defaults.stopGrace)
        // Fade Lengths': 1 s and 2 s, or greyed out; the fade-in alone
        // while nothing resumes.
        case .fadeLengths:
            SettingsTiming.fadeLengthsUnavailable(self)
                || timings.withDefaultFadeLengths(fadeIn: !SettingsTiming.fadeInUnused(self)) == timings
        // Volume Limits': 10 and 2 dB, or greyed out (leveling off or unavailable).
        case .volumeLimits: SettingsTiming.levelingLimitsUnavailable(self) || timings.withDefaultVolumeLimits == timings
        // Detection's: in AntiDot mode its way, what apps tell macOS; out
        // of it, the silence threshold at −60 dB (each greyed out in the other).
        case .detection:
            isAntiDotMode ? detectionMethod == .playbackSignals
                : timings.silenceThresholdDB == TimingSettings.defaults.silenceThresholdDB
        // Startup and Menu Bar's: launch at login off and the icon not kept
        // beside the system's, as on a fresh install.
        case .startup: !launchAtLoginEnabled && !keepsMenuBarIconNearSystemIcons
        // Updates': checked daily and installed automatically, as on a fresh
        // install; the choice counts as default while this copy can't install
        // updates (it's greyed out then).
        case .updates: checksForUpdatesAutomatically && (updateInstallNote != nil || automaticUpdates == .install)
        }
    }

    /// Sets the card's settings back to their defaults, leaving what's
    /// greyed out as it is.
    func restoreDefaults(_ card: SettingsCard) {
        switch card {
        case .pausing: setTimings(timings.withDefaultPausing)
        case .resuming: setTimings(timings.withDefaultResuming)
        case .fades:
            guard playerCanFade else { return }
            setTimings(timings.withDefaultFades)
        case .volume:
            guard !SettingsSwitch.levelsMusic.isUnavailable(self) else { return }
            setTimings(timings.withDefaultVolume)
        case .modes: setAntiDotMode(false)
        case .timing:
            var restored = timings
            restored.startConfirmation = TimingSettings.defaults.startConfirmation
            if timings.resumesPlayback { restored.stopGrace = TimingSettings.defaults.stopGrace }
            setTimings(restored)
        case .fadeLengths:
            guard !SettingsTiming.fadeLengthsUnavailable(self) else { return }
            setTimings(timings.withDefaultFadeLengths(fadeIn: !SettingsTiming.fadeInUnused(self)))
        case .volumeLimits:
            guard !SettingsTiming.levelingLimitsUnavailable(self) else { return }
            setTimings(timings.withDefaultVolumeLimits)
        // AntiDot mode's way in AntiDot mode, the silence threshold out of it.
        case .detection:
            if isAntiDotMode {
                setDetectionMethod(.playbackSignals)
            } else {
                var restored = timings
                restored.silenceThresholdDB = TimingSettings.defaults.silenceThresholdDB
                setTimings(restored)
            }
        // The icon no longer kept beside the system's stays where it is.
        case .startup:
            if launchAtLoginEnabled { setLaunchAtLogin(false) }
            if keepsMenuBarIconNearSystemIcons { setKeepsMenuBarIconNearSystemIcons(false) }
        // The choice left alone while this copy can't install updates.
        case .updates:
            if !checksForUpdatesAutomatically { updates.setChecksAutomatically(true) }
            if updateInstallNote == nil, automaticUpdates != .install { updates.setMode(.install) }
        }
    }
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
