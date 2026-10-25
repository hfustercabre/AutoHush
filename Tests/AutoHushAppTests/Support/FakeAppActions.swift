import Foundation
import AutoHushKit
@testable import AutoHushApp
import AutoHushTestSupport

/// What the stand-ins below were asked, in order, across them.
@MainActor
final class CallLog {
    var calls: [String] = []
}

/// Stands in for AppDelegate's part: each call is logged.
@MainActor
final class FakeAppActions: AppActions {
    let log: CallLog
    init(log: CallLog = CallLog()) { self.log = log }

    func choosePlayer(_ bundleID: String) { log.calls.append("player \(bundleID)") }
    func openAddWebApp() { log.calls.append("addWebApp") }
    func openAddApp() { log.calls.append("addApp") }
    func removeAddedApp(_ bundleID: String) { log.calls.append("remove \(bundleID)") }
    func reopenPlayer() { log.calls.append("reopenPlayer") }
    func unmutePlayer() { log.calls.append("unmutePlayer") }
    func retryResume() { log.calls.append("retryResume") }
    func learnControlsAgain() { log.calls.append("learnAgain") }
    func requestPermission(_ permission: Permission) { log.calls.append("warning \(permission.grantTitle)") }
    func finishWelcome() { log.calls.append("finishWelcome") }
    func refreshDiagnostics() { log.calls.append("refreshDiagnostics") }
    func menuWillOpen() { log.calls.append("menuWillOpen") }
    func reopenAutoHush() { log.calls.append("reopen") }
    func openSettings(page: SettingsWindowController.Page?) { log.calls.append(page.map { "\($0)" } ?? "settings") }
    func showControlError() { log.calls.append("why") }
    func showLogs() { log.calls.append("showLogs") }
    func openNotificationSettings() { log.calls.append("notificationSettings") }
    func moveMenuBarIconNearSystemIcons() { log.calls.append("moveMenuBarIcon") }
    func quit() { log.calls.append("quit") }
}

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
    func setChecksAutomatically(_ enabled: Bool) { log.calls.append("autoUpdate \(enabled)") }
    func setMode(_ mode: AutomaticUpdates) { log.calls.append("updates \(mode.rawValue)") }

    // What Settings shows of the updates, as the test sets it.
    var currentVersion: AppVersion?
    var checksAutomatically = true
    var mode = AutomaticUpdates.install
    var installUnavailability: UpdateInstallUnavailability?
    var status: String?
    var lastCheck: Date?
    var notificationsOff = false
}

extension UserSettings {
    /// The user's settings as in-memory preferences hold them.
    static func inMemory() -> UserSettings {
        UserSettings(preferences: Preferences(store: InMemoryPreferenceStore()))
    }
}

extension PlayerSession {
    /// A session with no player chosen, whose monitorings are stand-ins.
    static func noPlayer(settings: UserSettings = .inMemory()) -> PlayerSession {
        PlayerSession(player: nil, players: MusicPlayerCatalog(players: []),
                      preferences: Preferences(store: InMemoryPreferenceStore()),
                      settings: settings.state.monitoring, makeMonitoring: FakeMonitorings().make,
                      locateApp: { _ in nil })
    }
}
