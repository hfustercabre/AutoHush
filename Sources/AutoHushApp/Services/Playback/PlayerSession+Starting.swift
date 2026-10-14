import Foundation
import OSLog
import AutoHushKit

// PlayerSession: starting the player's monitoring.
extension PlayerSession {
    func requestStart(retries: Int = 0) {
        Task { await start(retriesLeft: retries) }
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
                logger.debug("\(player.name, privacy: .public) is not ready yet (\(error.localizedDescription, privacy: .public)) — retrying")
                try? await Task.sleep(for: .seconds(Self.startupRetryDelay))
                guard generation == startGeneration else { return } // Retry or another launch took over
                await start(retriesLeft: retriesLeft - 1)
                return
            }
            let problem = "\(player.name): \(error.localizedDescription)"
            if problem == loggedStartupProblem {
                logger.debug("Still can't control \(problem, privacy: .public)")
            } else {
                logger.error("Can't control \(problem, privacy: .public)")
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
            return
        }
        // A newer start (Retry, player relaunch) began while we awaited.
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
