import Foundation

// PlaybackArbiter: waiting for a pause or a resume under way.
extension PlaybackArbiter {
    /// Waits until no pause is under way. Tests use it to see a pause's outcome.
    func waitForPause() async {
        while let pauseTask { await pauseTask.value }
    }

    /// Waits until no resume is under way, the music fading back in
    /// included. A held pause's monitoring stops only then: stopping
    /// sooner would cut the fade-in short.
    package func waitForResume() async {
        while let resumeTask { await resumeTask.value }
    }

    /// Waits until nothing is left running: the pause under way, and a
    /// pending resume or pause whose debounce is over or that had none,
    /// called off ones included (`calledOff`). One still waiting on its
    /// debounce doesn't count. Tests use it before checking what happened,
    /// or that nothing did; their manual scheduler ends a debounce by
    /// cancelling it.
    func waitUntilIdle() async {
        var finished: Set<Task<Void, Never>> = []
        while true {
            let pending = [(pendingResumeTask, pendingResumeWait), (pendingPauseTask, pendingPauseWait)]
                + calledOff.values.map { ($0.task, $0.wait) }
            let running = ([pauseTask] + pending.filter { Self.isOver($0.1) }.map(\.0))
                .compactMap { $0 }.filter { !finished.contains($0) }
            guard let next = running.first else { return }
            await next.value
            finished.insert(next)
        }
    }

    /// The task of the pending resume or pause `id` ends: it's no longer
    /// one called off, nor left behind as the pending one.
    func pendingTaskEnded(_ id: UUID) {
        calledOff[id] = nil
        if pendingResumeID == id { pendingResumeTask = nil }
        if pendingPauseID == id { pendingPauseTask = nil }
    }

    private static func isOver(_ debounce: Task<Void, Never>?) -> Bool {
        debounce?.isCancelled ?? true
    }
}
