import Foundation
import AutoHushKit

// PlayerSession: the monitoring under way.
extension PlayerSession {
    /// Monitoring for `player`, whose updates come with `token`: the current
    /// one's are applied, not the last ones of a monitoring stopped while
    /// they were on their way; a held pause's stay with `heldPauses`. What
    /// AntiDot learned is the app's, whichever monitoring learned it.
    func makeMonitoring(for player: any MusicPlayer, token: UUID) -> any SessionMonitoring {
        let setup = MonitoringSetup(configuration: configuration(for: player), settings: settings,
                                    learnedAssertions: preferences.playbackAssertions, resumesHeld: resumesHeld)
        return monitoringMaker(player, setup) { [weak self, token] update in
            guard let self, !self.heldPauses.takes(update, from: token),
                  token == self.monitoringToken || Self.isLearned(update) else { return }
            self.apply(update)
        }
    }

    private static func isLearned(_ update: MonitoringPipeline.StatusUpdate) -> Bool {
        if case .learnedAssertions = update { true } else { false }
    }

    /// The engine's configuration: the user's timings, and the player, whose
    /// own audio never counts as another app playing. While it only lists
    /// the apps playing (`listenUntilPlayerOpens`), it looks at the idle
    /// rate: it can pause nothing, so the menu's lists may come up to a
    /// second late (S16, the full check, 2026-10-19).
    func configuration(for player: any MusicPlayer?) -> AppConfiguration {
        var configuration = AppConfiguration(timings: settings.timings)
        configuration.musicPlayerBundleID = player?.bundleID
        if waitsForPlayerToOpen { configuration.activeSampleInterval = configuration.idleSampleInterval }
        return configuration
    }

    private func apply(_ update: MonitoringPipeline.StatusUpdate) {
        switch update {
        case .playback(let playback):
            state.playback = playback
        case .activeSources(let sources):
            let othersStarted = state.activeSources.isEmpty && !sources.isEmpty
            // Recorded first: Settings → Sound Sources lists them as the state shows.
            preferences.recordSeen(sources)
            state.activeSources = sources
            if othersStarted { checkAccess() }
        case .detection(let mode):
            state.detection = mode
        case .learnedAssertions(let id, let assertions):
            preferences.playbackAssertions[id] = assertions
        case .pauseFailure(let error):
            state.controlError = error.map { ControlError($0, player: player?.name ?? "") }
        case .mutedInstead(let muted):
            state.mutedInstead = muted
        case .resumeFailure(let error):
            state.resumeError = error.map { ControlError($0, player: player?.name ?? "") }
        }
    }

    /// Each setting that changed goes to the monitorings that follow it.
    func follow(_ settings: MonitoringSettings, from old: MonitoringSettings) {
        if settings.autoPause != old.autoPause {
            monitoring?.setAutoPauseEnabled(settings.autoPause)
            heldPauses.setAutoPauseEnabled(settings.autoPause)
            // The player not running: the apps are listed only while it's on.
            if settings.autoPause {
                let id = UUID()
                startTasks[id] = Task {
                    await listenUntilPlayerOpens()
                    startTasks[id] = nil
                }
            } else {
                stopListeningUntilPlayerOpens()
            }
        }
        if settings.ignored != old.ignored {
            monitoring?.setIgnoredSources(settings.ignored)
            heldPauses.setIgnoredSources(settings.ignored)
        }
        if settings.timings != old.timings { monitoring?.setConfiguration(configuration(for: player)) }
        if settings.detection != old.detection {
            monitoring?.setDetectionMethod(settings.detection)
            heldPauses.setDetectionMethod(settings.detection)
        }
    }

    /// Without a monitoring nothing is known about the music: a state it left
    /// behind would otherwise hand over a pause that no longer exists, or
    /// keep automatic updates from ever finding a quiet moment. Its updates
    /// still on their way aren't applied either.
    func tearDownMonitoring() {
        monitoring?.stop()
        monitoring = nil
        monitoringToken = UUID()
        var stopped = state
        stopped.playback = .unknown
        stopped.detection = .pending
        stopped.mutedInstead = false
        stopped.resumeError = nil
        state = stopped
    }

    /// The health, and the apps playing, which none are unless it's ready.
    func setHealth(_ health: AppHealthState?) {
        var changed = state
        changed.health = health
        if health != .ready { changed.activeSources = [] }
        state = changed
    }
}
