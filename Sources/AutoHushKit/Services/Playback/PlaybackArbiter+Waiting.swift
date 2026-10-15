import Foundation

// PlaybackArbiter: waiting for a pause or a resume under way.
extension PlaybackArbiter {
    /// Waits until no pause is under way. Tests use it to see a pause's outcome.
    package func waitForPause() async {
        while let pauseTask { await pauseTask.value }
    }

    /// Waits until no resume is under way, the music fading back in
    /// included. A held pause's monitoring stops only then: stopping
    /// sooner would cut the fade-in short.
    package func waitForResume() async {
        while let resumeTask { await resumeTask.value }
    }

    /// Waits until nothing is left running: the pause under way, and a
    /// pending resume or pause whose debounce is over or that had none. One
    /// still waiting on its debounce doesn't count. Tests use it before
    /// checking what happened, or that nothing did; their manual scheduler
    /// ends a debounce by cancelling it.
    package func waitUntilIdle() async {
        var finished: Set<Task<Void, Never>> = []
        while true {
            let running = [
                pauseTask,
                Self.isOver(pendingResumeWait) ? pendingResumeTask : nil,
                Self.isOver(pendingPauseWait) ? pendingPauseTask : nil,
            ].compactMap { $0 }.filter { !finished.contains($0) }
            guard let next = running.first else { return }
            await next.value
            finished.insert(next)
        }
    }

    private static func isOver(_ debounce: Task<Void, Never>?) -> Bool {
        debounce?.isCancelled ?? true
    }
}
