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
struct SourceActivityTracker {
    /// What is known about one source.
    private struct Entry {
        /// When it was first heard, kept while it's tracked.
        let firstHeard: Date
        var pendingSince: Date?
        var lastAudible: Date
        var isActive: Bool
    }

    private(set) var startConfirmation: TimeInterval
    private(set) var gapTolerance: TimeInterval
    private(set) var stopGrace: TimeInterval

    private var entries: [String: Entry] = [:]

    /// Applies new timings; tracked sources keep their state.
    mutating func updateTimings(from configuration: AppConfiguration) {
        startConfirmation = configuration.sourceStartConfirmation
        gapTolerance = configuration.audibleGapTolerance
        stopGrace = configuration.sourceStopGrace
    }

    /// Sources that have started and not yet stopped.
    var activeSources: Set<String> {
        Set(entries.filter { $0.value.isActive }.keys)
    }

    /// True when the source is active or awaiting confirmation.
    func isTracking(_ id: String) -> Bool { entries[id] != nil }

    /// When a tracked source was first heard, before it counted as started;
    /// `nil` once it's forgotten.
    func firstHeard(_ id: String) -> Date? { entries[id]?.firstHeard }

    /// True when no source is active or awaiting confirmation.
    var isIdle: Bool { entries.isEmpty }

    /// `startConfirmations` replaces the start confirmation for some sources
    /// in this update (e.g. a longer one for sound without video).
    mutating func update(
        audible: Set<String>, at now: Date, startConfirmations: [String: TimeInterval] = [:]
    ) -> (started: Set<String>, stopped: Set<String>) {
        var started: Set<String> = []
        var stopped: Set<String> = []

        for bundleID in audible {
            // Only *observed* silence (second loop below) restarts a pending
            // confirmation; a delayed evaluation must not.
            var entry = entries[bundleID] ?? Entry(firstHeard: now, pendingSince: now, lastAudible: now, isActive: false)
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

    mutating func reset() {
        entries.removeAll()
    }
}

// In an extension, so the struct keeps its memberwise initializer
// (`init(startConfirmation:gapTolerance:stopGrace:)`; `entries` has a value
// and is private, so it's left out of it).
extension SourceActivityTracker {
    init(configuration: AppConfiguration) {
        self.init(
            startConfirmation: configuration.sourceStartConfirmation,
            gapTolerance: configuration.audibleGapTolerance,
            stopGrace: configuration.sourceStopGrace
        )
    }
}
