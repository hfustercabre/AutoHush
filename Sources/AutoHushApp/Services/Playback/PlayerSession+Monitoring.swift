import Foundation
import AutoHushKit

// PlayerSession: the monitoring under way.
extension PlayerSession {
    /// Monitoring for `player`, whose updates come with `token`: the current
    /// one's are applied; a held pause's stay with `heldPauses`.
    func makeMonitoring(for player: any MusicPlayer, token: UUID) -> any SessionMonitoring {
        let setup = MonitoringSetup(configuration: configuration(for: player), settings: settings,
                                    learnedAssertions: preferences.playbackAssertions, resumesHeld: resumesHeld)
        return monitoringMaker(player, setup) { [weak self, token] update in
            guard let self, !self.heldPauses.takes(update, from: token) else { return }
            self.apply(update)
        }
    }

    /// The engine's configuration: the user's timings, and the player, whose
    /// own audio never counts as another app playing.
    func configuration(for player: (any MusicPlayer)?) -> AppConfiguration {
        var configuration = AppConfiguration(timings: settings.timings)
        configuration.musicPlayerBundleID = player?.bundleID
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
        }
    }

    /// Each setting that changed goes to the monitorings that follow it.
    func follow(_ settings: MonitoringSettings, from old: MonitoringSettings) {
        if settings.autoPause != old.autoPause {
            monitoring?.setAutoPauseEnabled(settings.autoPause)
            heldPauses.setAutoPauseEnabled(settings.autoPause)
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
    /// keep automatic updates from ever finding a quiet moment.
    func tearDownMonitoring() {
        monitoring?.stop()
        monitoring = nil
        var stopped = state
        stopped.playback = .unknown
        stopped.detection = .pending
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
