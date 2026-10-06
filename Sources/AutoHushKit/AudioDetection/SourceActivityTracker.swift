import Foundation

/// Turns raw per-tick "is this source audible right now?" samples into stable
/// started/stopped transitions:
///
///   - A source starts only after it has been audible for `startConfirmation`
///     (gaps up to `gapTolerance` allowed), so notification blips never count.
///   - A started source stops only after it has been inaudible for `stopGrace`,
///     so gaps between tracks or videos do not bounce the music.
///
/// A pure value type driven by explicit timestamps, so it is fully deterministic.
package struct SourceActivityTracker {
    /// What is known about one source.
    private struct Entry {
        var pendingSince: Date?
        var lastAudible: Date
        var isActive: Bool
    }

    private(set) var startConfirmation: TimeInterval
    private(set) var gapTolerance: TimeInterval
    private(set) var stopGrace: TimeInterval

    private var entries: [String: Entry] = [:]

    package init(startConfirmation: TimeInterval, gapTolerance: TimeInterval, stopGrace: TimeInterval) {
        self.startConfirmation = startConfirmation
        self.gapTolerance = gapTolerance
        self.stopGrace = stopGrace
    }

    package init(configuration: AppConfiguration) {
        self.init(
            startConfirmation: configuration.sourceStartConfirmation,
            gapTolerance: configuration.audibleGapTolerance,
            stopGrace: configuration.sourceStopGrace
        )
    }

    /// Applies new timings; tracked sources keep their state.
    package mutating func updateTimings(from configuration: AppConfiguration) {
        startConfirmation = configuration.sourceStartConfirmation
        gapTolerance = configuration.audibleGapTolerance
        stopGrace = configuration.sourceStopGrace
    }

    /// Sources that have started and not yet stopped.
    package var activeSources: Set<String> {
        Set(entries.filter { $0.value.isActive }.keys)
    }

    /// True when the source is active or awaiting confirmation.
    package func isTracking(_ id: String) -> Bool { entries[id] != nil }

    /// True when no source is active or awaiting confirmation.
    package var isIdle: Bool { entries.isEmpty }

    /// `startConfirmations` replaces the start confirmation for some sources
    /// in this update (e.g. a longer one for sound without video).
    package mutating func update(
        audible: Set<String>, at now: Date, startConfirmations: [String: TimeInterval] = [:]
    ) -> (started: Set<String>, stopped: Set<String>) {
        var started: Set<String> = []
        var stopped: Set<String> = []

        for bundleID in audible {
            // Only *observed* silence (second loop below) restarts a pending
            // confirmation; a delayed evaluation must not.
            var entry = entries[bundleID] ?? Entry(pendingSince: now, lastAudible: now, isActive: false)
            entry.lastAudible = now
            let confirmation = startConfirmations[bundleID] ?? startConfirmation
            if !entry.isActive, now.timeIntervalSince(entry.pendingSince ?? now) >= confirmation {
                entry.isActive = true
                entry.pendingSince = nil
                started.insert(bundleID)
            }
            entries[bundleID] = entry
        }

        for (bundleID, entry) in entries where !audible.contains(bundleID) {
            let silentFor = now.timeIntervalSince(entry.lastAudible)
            if entry.isActive {
                if silentFor >= stopGrace {
                    entries[bundleID] = nil
                    stopped.insert(bundleID)
                }
            } else if silentFor > gapTolerance {
                entries[bundleID] = nil
            }
        }

        return (started, stopped)
    }

    package mutating func reset() {
        entries.removeAll()
    }
}
