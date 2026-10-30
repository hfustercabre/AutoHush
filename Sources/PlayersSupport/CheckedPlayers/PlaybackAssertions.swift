import Foundation
import os
import AutoHushKit

/// What an added app's keep-awake assertions say, by AntiDot mode's rule
/// (`AnnouncedAssertions.announcing`, its names learned while its sound is
/// on; one keeping only the display awake doesn't tell, unless it's one of
/// its video names): playing while it announces, paused once it has
/// before; `.unknown` until it has. What it learned is kept under a lock,
/// so reads made at once lose none of it.
final class PlaybackAssertions: Sendable {
    /// What the app's own processes hold now.
    static let read: @Sendable (pid_t) -> Set<PowerAssertion> = { IOKitPowerAssertionReader().assertions(ownedBy: $0) }

    private let read: @Sendable (pid_t) -> Set<PowerAssertion>
    /// The names it announces with, and whether it has announced yet.
    private let learned = OSAllocatedUnfairLock(initialState: (announced: AnnouncedAssertions(), seen: false))

    init(read: @escaping @Sendable (pid_t) -> Set<PowerAssertion>) {
        self.read = read
    }

    /// `soundOn`: whether its sound output is on, asked only while it holds
    /// one. Its reads block: made on its player's queue.
    func state(of pid: pid_t, soundOn: () -> Bool) -> PlayerState {
        let held = read(pid)
        let learns = !held.isEmpty && soundOn()
        return learned.withLock { learned in
            if learns { learned.announced.learn(held) }
            if learned.announced.announcing(held) {
                learned.seen = true
                return .playing
            }
            return learned.seen ? .paused : .unknown
        }
    }
}
