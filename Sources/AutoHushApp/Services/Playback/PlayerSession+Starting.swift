import Foundation
import AutoHushKit

// PlayerSession: starting the player's monitoring.
extension PlayerSession {
    func requestStart(retries: Int = 0) {
        let id = UUID()
        startTasks[id] = Task {
            await start(retriesLeft: retries)
            startTasks[id] = nil
        }
    }

    /// Returns once no start and no access check is under way: tests use it
    /// to see that nothing more happens.
    func waitUntilIdle() async {
        while let task = startTasks.values.first ?? accessCheck { await task.value }
    }

    /// Errors that mean the player is not ready yet rather than a lasting problem.
    nonisolated static func isTransientStartupError(_ error: any Error) -> Bool {
        switch error as? MusicPlayerError {
        case .playerNotResponding, .playerNotRunning: return true
        default:                                         return false
        }
    }

    func start(retriesLeft: Int = 0) async {
        guard !hasQuit else { return }
        startGeneration += 1
        let generation = startGeneration
        cancelRetry() // this start takes its place
        tearDownMonitoring()
        waitsForPlayerToOpen = false
        guard let player else {
            setHealth(nil) // nothing to control yet
            return
        }
        // Where the player says, else where macOS knows it, as the players are listed.
        guard player.installedURL ?? locateApp(player.bundleID) != nil else {
            setHealth(.playerNotInstalled(player.name))
            return
        }

        do {
            try await player.verifyControlAccess()
        } catch {
            guard generation == startGeneration else { return }
            if retriesLeft > 0, Self.isTransientStartupError(error) {
                logger.debug("\(player.name, privacy: .public) is not ready yet (\(error)) — retrying")
                await retries.startupWait(.seconds(Self.startupRetryDelay))
                guard generation == startGeneration else { return } // Try Again or another launch took over
                await start(retriesLeft: retriesLeft - 1)
                return
            }
            let problem = "\(player.name): \(LogMessage.englishDescription(of: error))"
            if problem == loggedStartupProblem {
                logger.debug("Still can’t control \(problem, privacy: .public)")
            } else {
                logger.error("Can’t control \(problem, privacy: .public)")
                loggedStartupProblem = problem
            }
            // The line says AutoHush can't control it: the menu tells why.
            var failed = state
            switch error as? MusicPlayerError {
            case .playerCommandFailed?, .stillLearning?, nil: failed.controlError = ControlError(error, player: player.name)
            default: failed.controlError = nil
            }
            state = failed
            setHealth(AppHealthState(startupError: error, playerName: player.name))
            retryLater(after: error)
            if case .playerNotRunning? = error as? MusicPlayerError {
                waitsForPlayerToOpen = true
                await listenUntilPlayerOpens()
            }
            return
        }
        // A newer start (Try Again, player relaunch) began while we awaited.
        guard generation == startGeneration else { return }

        let token = UUID()
        monitoringToken = token
        let monitoring = makeMonitoring(for: player, token: token)
        self.monitoring = monitoring
        // Both asked every time: each answers once.
        let takesBack = heldPauses.takesBack(player.bundleID)
        let takesOver = takesOverPause()
        await monitoring.start(takingOverPause: takesOver || takesBack, asleep: isAsleep)
        guard generation == startGeneration else { return }
        failedStarts = 0
        loggedStartupProblem = nil
        var started = state
        started.controlError = nil
        state = started
        setHealth(.ready)
    }

    /// While the chosen player isn't running and Auto-Pause is on, its
    /// monitoring runs all the same, so the menu lists the apps playing and
    /// played (the user, 2026-10-18: "Keep listing them if the player isn't
    /// running but the Auto-Pause is on"); it finds nothing to pause, and the
    /// status line still says the player isn't running. The player opening
    /// starts it as usual (`start`).
    func listenUntilPlayerOpens() async {
        guard !hasQuit, waitsForPlayerToOpen, settings.autoPause, monitoring == nil, let player else { return }
        let token = UUID()
        monitoringToken = token
        let monitoring = makeMonitoring(for: player, token: token)
        self.monitoring = monitoring
        await monitoring.start(takingOverPause: false, asleep: isAsleep)
    }

    /// Auto-Pause turned off (or off for a while) while the player isn't
    /// running: the apps aren't listed until it's on again.
    func stopListeningUntilPlayerOpens() {
        guard waitsForPlayerToOpen, monitoring != nil else { return }
        tearDownMonitoring()
        state.activeSources = []
    }

    /// Tries starting again after `error`, unless an event will: see `Retries`.
    private func retryLater(after error: any Error) {
        let delay: TimeInterval
        switch error as? MusicPlayerError {
        case .playerNotRunning:
            return // started on when the player opens
        case .automationPermissionDenied, .accessibilityPermissionDenied:
            delay = retries.permissionInterval
        default:
            failedStarts += 1
            delay = Self.retryDelay(afterFailedStarts: failedStarts, delays: retries.delays)
        }
        cancelRetry()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.retryTimer = nil
                self?.requestStart()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    func cancelRetry() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    /// The wait before starting again after `failedStarts` failed starts in a
    /// row: the range's lower bound, doubling up to its upper bound.
    nonisolated static func retryDelay(afterFailedStarts failedStarts: Int, delays: ClosedRange<TimeInterval>) -> TimeInterval {
        min(delays.lowerBound * pow(2, Double(max(failedStarts - 1, 0))), delays.upperBound)
    }
}
