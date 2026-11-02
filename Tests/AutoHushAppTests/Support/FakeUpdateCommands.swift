import Foundation
import AutoHushKit
@testable import AutoHushApp

/// Stands in for the updates: each command is logged; what Settings shows
/// of them is as the test sets it.
@MainActor
final class FakeUpdateCommands: UpdateCommands {
    let log: CallLog
    init(log: CallLog = CallLog()) { self.log = log }

    func checkFromUser() { log.calls.append("checkUpdates") }

    /// `checkNow` waits for `finishCheck()` while this is set.
    var holdsChecks = false
    private var heldCheck: CheckedContinuation<Void, Never>?

    func checkNow() async {
        log.calls.append("checkNow")
        if holdsChecks { await withCheckedContinuation { heldCheck = $0 } }
    }

    func finishCheck() {
        heldCheck?.resume()
        heldCheck = nil
    }
    func presentAvailableUpdate() { log.calls.append("update") }
    /// The choices' commands change what Settings shows of them too, as
    /// the real updates' do; off, only the test changes it.
    var followsCommands = false

    func setChecksAutomatically(_ enabled: Bool) {
        log.calls.append("autoUpdate \(enabled)")
        if followsCommands { checksAutomatically = enabled }
    }

    func setMode(_ mode: AutomaticUpdates) {
        log.calls.append("updates \(mode.rawValue)")
        if followsCommands { self.mode = mode }
    }

    func setGetsReleaseCandidates(_ enabled: Bool) {
        log.calls.append("releaseCandidates \(enabled)")
        if followsCommands { getsReleaseCandidates = enabled }
    }

    // What Settings shows of the updates, as the test sets it.
    var currentVersion: AppVersion?
    var checksAutomatically = true
    var mode = AutomaticUpdates.install
    var getsReleaseCandidates = false
    var availableUpdate: AppRelease?
    var installUnavailability: UpdateInstallUnavailability?
    var status: String?
    var lastCheck: Date?
    var notificationsOff = false
}
