import Foundation

/// Where preferences are kept: `UserDefaults` in the app, memory in tests.
package protocol PreferenceStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: PreferenceStore {}

/// User choices that persist across launches, stored in `UserDefaults`.
@MainActor
package final class Preferences {
    enum Key {
        static let autoPauseEnabled = "autoPauseEnabled"
        static let autoPauseSnoozedUntil = "autoPauseSnoozedUntil"
        static let focusNotedAutoPauseEnabled = "focusNotedAutoPauseEnabled"
        static let focusNotedAutoPauseSnoozedUntil = "focusNotedAutoPauseSnoozedUntil"
        static let focusAppliedAutoPause = "focusAppliedAutoPause"
        static let ignoredApps = "ignoredApps"
        static let appsIgnoredByDefault = "appsIgnoredByDefault"
        static let seenApps = "seenApps"
        static let appListOrder = "appListOrder"
        static let appListOrderReversed = "appListOrderReversed"
        static let timings = "timings"
        static let checksForUpdates = "checksForUpdatesAutomatically"
        static let automaticUpdates = "automaticUpdates"
        static let getsReleaseCandidates = "getsReleaseCandidates"
        /// Earlier on/off switch; `false` maps to `.notify`.
        static let legacyInstallsUpdates = "installsUpdatesAutomatically"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let downloadedUpdate = "downloadedUpdate"
        static let expiredUpdateVersion = "expiredUpdateVersion"
        static let lastUpdateNotice = "lastUpdateNotice"
        static let lastLaunchedVersion = "lastLaunchedVersion"
        static let pauseHandedOver = "pauseHandedOverAt"
        static let pauseHandedOverPlayer = "pauseHandedOverPlayer"
        static let detectionMethod = "detectionMethod"
        static let antiDotMethod = "antiDotMethod"
        static let playbackAssertions = "playbackAssertions"
        /// Earlier list of apps seen announcing playback, without the names
        /// AntiDot mode now learns; dropped, so apps are learned again.
        static let legacyAnnouncingApps = "announcingApps"
        /// Earlier on/off switch; `false` maps to `.openStreams`.
        static let legacyMeasuresAudioLevels = "measuresAudioLevels"
        static let musicPlayer = "musicPlayer"
        static let webAppButtons = Preferences.webAppButtonsKey
        /// Set once the media player could be chosen (see `keepFormerPlayer`).
        static let playerChoiceIntroduced = "playerChoiceIntroduced"
        /// Kept by any earlier AutoHush that ran on this Mac.
        static let earlierVersionKeys = [
            lastLaunchedVersion, lastUpdateCheck, seenApps, ignoredApps, autoPauseEnabled, timings,
            detectionMethod, legacyMeasuresAudioLevels, checksForUpdates, automaticUpdates, legacyInstallsUpdates,
        ]
    }

    /// Each web app's learned Play/Pause button, by its bundle ID. The
    /// players read and save theirs from their own queues (`UserDefaults` is
    /// thread-safe); this class only clears out old ones.
    package nonisolated static let webAppButtonsKey = "webAppPlayPauseButtons"

    /// How many apps that played audio are remembered for Settings → Sound Sources.
    static let seenAppsLimit = 50

    let defaults: any PreferenceStore

    package init(store: any PreferenceStore = UserDefaults.standard) {
        self.defaults = store
    }

    package var autoPause: AutoPauseSetting {
        get {
            AutoPauseSetting(
                isEnabled: defaults.object(forKey: Key.autoPauseEnabled) as? Bool ?? true,
                snoozedUntil: defaults.object(forKey: Key.autoPauseSnoozedUntil) as? Date
            )
        }
        set {
            defaults.set(newValue.isEnabled, forKey: Key.autoPauseEnabled)
            defaults.set(newValue.snoozedUntil, forKey: Key.autoPauseSnoozedUntil)
        }
    }

    /// What a Focus noted of Auto-Pause, until the Focus ends; `nil` when
    /// none is on. Saved so a quit or a restart during the Focus still ends
    /// with Auto-Pause put back. Setting `nil` removes it.
    package var focusAutoPause: FocusAutoPauseNote? {
        get {
            guard let applied = defaults.object(forKey: Key.focusAppliedAutoPause) as? Bool else { return nil }
            return FocusAutoPauseNote(
                noted: AutoPauseSetting(
                    isEnabled: defaults.object(forKey: Key.focusNotedAutoPauseEnabled) as? Bool ?? true,
                    snoozedUntil: defaults.object(forKey: Key.focusNotedAutoPauseSnoozedUntil) as? Date
                ),
                applied: applied
            )
        }
        set {
            defaults.set(newValue?.noted.isEnabled, forKey: Key.focusNotedAutoPauseEnabled)
            defaults.set(newValue?.noted.snoozedUntil, forKey: Key.focusNotedAutoPauseSnoozedUntil)
            defaults.set(newValue?.applied, forKey: Key.focusAppliedAutoPause)
        }
    }

    /// Each timing's key in the stored dictionary. A missing key keeps its default.
    /// The switches are stored there too, as 1 or 0 (`switchKeys`).
    private static let timingKeys: [(key: String, value: WritableKeyPath<TimingSettings, Double>)] = [
        ("startConfirmation", \.startConfirmation),
        ("stopGrace", \.stopGrace),
        ("silenceThresholdDB", \.silenceThresholdDB),
        ("fadeOutDuration", \.fadeOutDuration),
        ("fadeInDuration", \.fadeInDuration),
        ("levelingMaxCutDB", \.levelingMaxCutDB),
        ("levelingMinCutDB", \.levelingMinCutDB),
    ]
    private static let switchKeys: [(key: String, value: WritableKeyPath<TimingSettings, Bool>)] = [
        ("fadesEnabled", \.fadesEnabled),
        ("pausesOnOutputDisconnect", \.pausesOnOutputDisconnect),
        ("resumesPlayback", \.resumesPlayback),
        ("levelsMusic", \.levelsMusic),
        ("pausesForMicrophone", \.pausesForMicrophone),
        ("staysPausedAfterCalls", \.staysPausedAfterCalls),
    ]

    package var timings: TimingSettings {
        get {
            let stored = defaults.object(forKey: Key.timings) as? [String: Double] ?? [:]
            var timings = TimingSettings.defaults
            for (key, value) in Self.timingKeys {
                if let number = stored[key] { timings[keyPath: value] = number }
            }
            for (key, value) in Self.switchKeys {
                if let number = stored[key] { timings[keyPath: value] = number != 0 }
            }
            return timings.clamped
        }
        set {
            let value = newValue.clamped
            var stored = Dictionary(uniqueKeysWithValues: Self.timingKeys.map { ($0.key, value[keyPath: $0.value]) })
            for (key, path) in Self.switchKeys { stored[key] = value[keyPath: path] ? 1 : 0 }
            defaults.set(stored, forKey: Key.timings)
        }
    }

    /// Forgets the learned buttons of web apps for which `isGone` is true
    /// (deleted: adding a site again makes a new app, with a new ID).
    package func forgetWebAppButtons(where isGone: (String) -> Bool) {
        // The players change them from their own queues (`KeyedDefaults`).
        KeyedDefaults.lock.withLock {
            guard let stored = defaults.object(forKey: Key.webAppButtons) as? [String: Any] else { return }
            let kept = stored.filter { !isGone($0.key) }
            if kept.count != stored.count { defaults.set(kept, forKey: Key.webAppButtons) }
        }
    }

    /// The bundle ID of the media player AutoHush controls; `nil` until the
    /// user chooses one.
    package var musicPlayer: String? {
        get { defaults.object(forKey: Key.musicPlayer) as? String }
        set { defaults.set(newValue, forKey: Key.musicPlayer) }
    }

    /// AutoHush controlled one player before it could be chosen. On the first
    /// launch of a version with the choice, someone updating (an earlier
    /// AutoHush left its settings) keeps that player instead of being asked.
    /// Call it before anything else is stored at launch. Later launches leave
    /// the choice alone, so a new user who hasn't chosen yet is still asked.
    package func keepFormerPlayer(_ bundleID: String?) {
        guard defaults.object(forKey: Key.playerChoiceIntroduced) == nil else { return }
        defaults.set(true, forKey: Key.playerChoiceIntroduced)
        guard musicPlayer == nil, let bundleID,
              Key.earlierVersionKeys.contains(where: { defaults.object(forKey: $0) != nil })
        else { return }
        musicPlayer = bundleID
    }

    /// Settings → Behavior's AntiDot mode and Fine-Tuning's way of detecting.
    package var detectionMethod: DetectionMethod {
        get {
            if let stored = (defaults.object(forKey: Key.detectionMethod) as? String).flatMap(DetectionMethod.init) {
                return stored
            }
            return defaults.object(forKey: Key.legacyMeasuresAudioLevels) as? Bool == false ? .openStreams : .audioLevels
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.detectionMethod)
            defaults.set(nil, forKey: Key.legacyMeasuresAudioLevels)
        }
    }

    /// AntiDot mode's way chosen last, which it's turned on with again (the
    /// user, 2026-10-20); by what apps tell macOS until one is chosen.
    package var antiDotMethod: DetectionMethod {
        get {
            if let stored = (defaults.object(forKey: Key.antiDotMethod) as? String).flatMap(DetectionMethod.init), stored.isAntiDot {
                return stored
            }
            return detectionMethod.isAntiDot ? detectionMethod : .defaultAntiDot
        }
        set {
            guard newValue.isAntiDot else { return }
            defaults.set(newValue.rawValue, forKey: Key.antiDotMethod)
        }
    }

    /// What AntiDot mode learned about how apps tell macOS they play: the
    /// names of the power assertions each app held while its sound was on.
    package var playbackAssertions: [String: AnnouncedAssertions] {
        get {
            let stored = defaults.object(forKey: Key.playbackAssertions) as? [String: [String: [String]]] ?? [:]
            return stored.mapValues { AnnouncedAssertions(system: Set($0["system"] ?? []), display: Set($0["display"] ?? [])) }
        }
        set {
            let stored = newValue.mapValues { ["system": $0.system.sorted(), "display": $0.display.sorted()] }
            defaults.set(stored, forKey: Key.playbackAssertions)
            defaults.set(nil, forKey: Key.legacyAnnouncingApps)
        }
    }

    /// The pause AutoHush last handed over when it quit while holding the
    /// music paused (to install an update, say); the next AutoHush takes it
    /// over.
    package var pauseHandover: PauseHandover? {
        get {
            guard let at = defaults.object(forKey: Key.pauseHandedOver) as? Date else { return nil }
            // AutoHush 0.8.2 and earlier write the date alone and leave the
            // player as it was: it's this pause's only if written with it.
            let named = defaults.object(forKey: Key.pauseHandedOverPlayer) as? [String: Any]
            let namedAt = named?["at"] as? Date
            let isThisPause = namedAt.map { abs($0.timeIntervalSince(at)) < 1 } ?? false
            guard isThisPause, let named else { return PauseHandover(at: at, player: nil) }
            // Before 0.11.1 there was only the chosen player's pause.
            return PauseHandover(at: at, player: named["player"] as? String,
                                 holdsChosen: named["chosen"] as? Bool ?? true, held: named["held"] as? [String] ?? [])
        }
        set {
            defaults.set(newValue?.at, forKey: Key.pauseHandedOver)
            let named: [String: Any]? = newValue.flatMap { handover in
                guard handover.player != nil || !handover.holdsChosen || !handover.held.isEmpty else { return nil }
                var named: [String: Any] = ["at": handover.at, "chosen": handover.holdsChosen, "held": handover.held]
                if let player = handover.player { named["player"] = player }
                return named
            }
            defaults.set(named, forKey: Key.pauseHandedOverPlayer)
        }
    }
}
