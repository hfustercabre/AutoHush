import Darwin

/// AntiDot mode's "What apps tell macOS": judges apps by what they tell macOS
/// instead of by their sound, so nothing is captured.
///
/// An app holding its own "don't sleep" power assertion counts as playing.
/// One seen doing that before but not now counts as paused, even with its
/// audio still open; such apps are remembered (`announcingSourceIDs`, saved
/// across launches by the app). Apps that never hold one get no verdict here
/// and are judged by their open output instead.
struct PlaybackSignals {
    private let powerAssertions: (any PowerAssertionReading)?
    /// Apps seen announcing playback through a power assertion.
    private(set) var announcingSourceIDs: Set<String>

    init(powerAssertions: (any PowerAssertionReading)?, announcingSourceIDs: Set<String>) {
        self.powerAssertions = powerAssertions
        self.announcingSourceIDs = announcingSourceIDs
    }

    /// The apps among `present` announcing playback right now: a process of
    /// theirs holds a system-sleep assertion. `owner` finds the app a process
    /// belongs to (a helper may hold the assertion for its app).
    func appsAnnouncingPlayback(among present: Set<String>, owner: (pid_t) -> String?) -> Set<String> {
        guard let powerAssertions, !present.isEmpty else { return [] }
        return Set(powerAssertions.pidsKeepingSystemAwake().compactMap(owner)).intersection(present)
    }

    /// Whether an app counts as playing: yes while it announces playback, no
    /// once it stopped announcing, `nil` (no verdict) if it never announced.
    func isPlaying(_ id: String, isAnnouncing: Bool) -> Bool? {
        if isAnnouncing { return true }
        return announcingSourceIDs.contains(id) ? false : nil
    }

    /// Remembers an app that announces playback; `true` the first time.
    mutating func remember(_ id: String) -> Bool {
        announcingSourceIDs.insert(id).inserted
    }
}
