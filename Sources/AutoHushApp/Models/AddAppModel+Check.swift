import Foundation
import CheckedPlayers
import PlayerCheckKit

// AddAppModel: the check itself, from the warning before it to what it found.
extension AddAppModel {
    /// What the check mutes while it plays and pauses the app.
    enum CheckMuting {
        /// The app itself, by tapping its sound: Audio Recording allowed,
        /// AntiDot mode off.
        case app
        /// The Mac's output, since the app alone can't be (the user, 2026-10-18).
        case mac
        /// Nothing: the output has no mute control, so the app is heard.
        case none
    }

    var checkMuting: CheckMuting {
        if permissions.audio == .allowed && !antiDot { return .app }
        return macCanMute ? .mac : .none
    }

    func readMacMuting() {
        let canMute = presenter?.canMuteOutput ?? false
        if canMute != macCanMute { macCanMute = canMute }
    }

    /// The check step's Continue…: the warning before the check.
    func continueToCheck() {
        guard stage == .ready else { return }
        readMacMuting() // what the warning says, and the check does
        presenter?.showWarning()
    }

    /// The warning's Start: the check runs, with its panel, once a stopped
    /// one has put things back; once it ends, what it found (or why it didn't).
    func startCheck() {
        guard stage == .ready, windowIsOpen, let app = chosen else { return }
        progress = CheckProgress()
        failureReason = nil
        pickedWay = nil
        isStopping = false
        stage = .checking
        Task { [weak self] in
            if let ending = self?.endingRun { _ = await ending.waitForEnd() }
            guard let self, self.stage == .checking, self.windowIsOpen, self.run == nil else { return }
            guard let run = self.helper?.startCheck(app, taps: !self.antiDot, onLine: { [weak self] line in self?.progress.add(line) }) else {
                self.stage = .failed
                self.failureReason = .other
                return
            }
            self.run = run
            self.presenter?.checkStarted(app)
            let end = await run.waitForEnd()
            self.ended(run, end, app: app)
        }
    }

    /// A check ended: the panel goes; for the check under way, what it found.
    private func ended(_ ending: any CheckRunning, _ end: PlayerCheckEnd, app: CheckableApp) {
        if endingRun === ending {
            endingRun = nil
            isEndingLastCheck = false
            if run == nil { presenter?.checkEnded() }
            return
        }
        guard run === ending else { return } // started again since
        presenter?.checkEnded()
        run = nil
        isStopping = false
        switch end {
        case .finished(let result?):
            if result.setup == nil, !reader.isRunning(app.bundleID) {
                // It quit during the check: nothing could be tried.
                failureReason = .appQuit
                stage = .failed
                return
            }
            stage = .done(result)
            keptChecks.save(KeptCheck(app: app, result: result, at: now(),
                                               needsReopen: needsReopen, reopenOutcome: reopenOutcome))
            // What muting needs, as it stands now (the last step may offer it).
            if choosableWays.isEmpty, let traits {
                Task { [weak self] in await self?.refreshPermissions(for: app, scriptable: traits.scriptable) }
            }
        case .finished(nil), .failed, .stopped:
            // A check again of an app whose result is kept (Check Again
            // beside Use) that doesn't finish: that result comes back, Use
            // with it (the workflow audit, 2026-10-22).
            // Not for an app gone from where it was: Use couldn't work.
            if let kept = keptChecks.load(now: now()), kept.app.bundleID == app.bundleID, reader.appExists(at: kept.app.url) {
                restore(kept)
            } else if case .stopped = end {
                stage = .stopped
            } else {
                appNotFound = !reader.appExists(at: app.url)
                failureReason = appNotFound ? .appNotFound : !reader.isRunning(app.bundleID) ? .appQuit : .other
                stage = .failed
            }
        case .permissionMissing:
            permissionMissingInCheck = true
            // The check's helper, a new process, found it missing; AutoHush,
            // which read it as the check started, may still read it allowed.
            accessibilityNeedsReopen = permissions.neededAllowed
            stage = .allowing
            watchPermissions()
        }
    }

    /// Stop (the window's, the panel's): the check puts everything back
    /// first. While the last one still does, the new one never starts: back
    /// to its step (the workflow audit, 2026-10-22).
    func stopCheck() {
        guard let run else {
            if stage == .checking { stage = .ready }
            return
        }
        isStopping = true
        run.stop()
    }

    /// After a check that stopped or failed, or one whose last step offers
    /// it (`offersCheckAgain`): from playing again.
    func checkAgain() {
        switch stage {
        case .stopped, .failed, .playTimedOut: waitForPlaying()
        case .done where offersCheckAgain: waitForPlaying()
        default: break
        }
    }

    /// There's a check's log to show.
    var canShowLog: Bool { presenter?.hasCheckLog ?? false }

    /// Shows the newest check's log (after one couldn't finish).
    func showLog() {
        presenter?.showCheckLog()
    }

    /// Stops a check under way: it puts things back before it ends, and the
    /// next one waits for that (`isEndingLastCheck`).
    func stopRun() {
        guard let run else { return }
        run.stop()
        self.run = nil
        endingRun = run
        isEndingLastCheck = true
    }
}
