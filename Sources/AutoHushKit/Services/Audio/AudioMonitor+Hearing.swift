import CoreAudio
import Foundation

// AudioMonitor: whether the media player is heard, measured alongside
// other apps (`playerHearing`).
extension AudioMonitor {
    /// Whether the media player is heard, from the levels measured while
    /// another app plays (the player is tapped alongside it): instant, so
    /// a pause waits for nothing. `.unknown` when levels aren't measured
    /// (AntiDot mode, Open audio streams only, no Audio Recording) or the
    /// player's processes aren't yet; `.silent` with no output of its own.
    /// With `since`, only its sound after then counts (what came before
    /// AutoHush's pause doesn't), and its silence is measured from then.
    func playerHearing(since: Date? = nil) async -> PlayerHearing {
        await queue.run { self.currentPlayerHearing(since: since) }
    }

    private func currentPlayerHearing(since: Date? = nil) -> PlayerHearing {
        guard detectionMethod == .audioLevels, detectionMode == .audioLevel else { return .unknown }
        guard !playerProcesses.isEmpty else { return .silent }
        // As of the latest look: what was measured, however long ago it ran.
        guard let playerMeasuredSince, let playerMeasuredAt else { return .unknown }
        let from = max(playerMeasuredSince, since ?? .distantPast)
        if let playerHeardAt, playerHeardAt >= from,
           playerMeasuredAt.timeIntervalSince(playerHeardAt) < Self.playerSilenceWindow { return .heard }
        let measured = playerMeasuredAt.timeIntervalSince(from)
        return measured >= Self.playerSilenceWindow ? .silent : .measuring(remaining: Self.playerSilenceWindow - measured)
    }

    /// Notes since when the player's processes are measured and when it was
    /// last heard (`playerHearing`); forgotten once they aren't measured.
    func notePlayerHearing(levels: [AudioObjectID: AudioLevel], at now: Date) {
        let peaks = playerProcesses.compactMap { levels[$0]?.peak }
        guard detectionMode == .audioLevel, !peaks.isEmpty else {
            playerMeasuredSince = nil
            playerMeasuredAt = nil
            playerHeardAt = nil
            return
        }
        let wasHeard = playerHeardAt.map { now.timeIntervalSince($0) < Self.playerSilenceWindow } ?? false
        playerMeasuredSince = playerMeasuredSince ?? now
        playerMeasuredAt = now
        guard peaks.contains(where: { $0 >= configuration.audibleThreshold }) else { return }
        playerHeardAt = now
        if !wasHeard { events.yield(.playerHeard) } // heard again: the arbiter looks at once
    }
}
