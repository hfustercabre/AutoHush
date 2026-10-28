import AutoHushKit

/// What a monitoring pipeline reported, in order, with each kind read apart.
/// Shared by the engine's tests and the app's (the player session's
/// pipelines).
@MainActor
package final class PipelineUpdates {
    package var all: [MonitoringStatusUpdate] = []

    package nonisolated init() {}

    package var activeSources: [[AudioSource]] {
        all.compactMap { if case .activeSources(let sources) = $0 { sources } else { nil } }
    }

    package var playback: [PlaybackState] {
        all.compactMap { if case .playback(let state) = $0 { state } else { nil } }
    }

    package var detection: [DetectionMode] {
        all.compactMap { if case .detection(let mode) = $0 { mode } else { nil } }
    }

    /// Why the music couldn't be paused (the updates saying it's over left out).
    package var pauseFailures: [MusicPlayerError] {
        all.compactMap { if case .pauseFailure(let error?) = $0 { error } else { nil } }
    }

    /// What AntiDot learned, the latest for each app.
    package var learned: [String: AnnouncedAssertions] {
        all.reduce(into: [:]) { if case .learnedAssertions(let id, let assertions) = $1 { $0[id] = assertions } }
    }
}
