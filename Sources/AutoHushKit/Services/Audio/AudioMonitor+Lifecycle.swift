import CoreAudio
import Foundation
import os

// AudioMonitor: starting and stopping.
extension AudioMonitor {
    func startOnQueue() {
        guard !isStarted else { return }
        isStarted = true

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer

        snapshotProvider.startObserving(on: queue) { [weak self] in
            guard let self else { return }
            self.needsRefresh = true
            self.lastHALChange = self.clock()
            self.tick()
        }
        needsRefresh = true
        tick()
    }

    func stopOnQueue() {
        guard isStarted else { return }
        isStarted = false

        timer?.cancel()
        timer = nil
        timerInterval = nil
        audioLevelsRelease?.cancel()
        audioLevelsRelease = nil
        snapshotProvider.stopObserving()
        levelMeter?.stopAll()
        resumeLevel = ResumeLevel()
        callSourceIDs = []

        candidates = []
        playerProcesses = []
        sourceOfProcess = [:]
        presentSourceIDs = []
        knownSources = [:]
        tracker.reset()
        signals.forgetAnnouncements()
        lastRefresh = nil
        lastHALChange = nil
        playerTapSince = nil
        silentSince = [:]
        quietProcesses = []
        quietListenedAt = nil
        quietListenUntil = nil
        quietListenHeard = false
        endQuietListenAsk()
        lastPermissionCheck = nil
        publishedLocalPlayback = nil
        publishedStartConfirmation = nil
        publishActiveSources()
        latestReport.withLock { $0 = nil }
    }
}
