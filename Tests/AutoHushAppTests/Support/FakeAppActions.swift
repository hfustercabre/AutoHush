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
    func learnControlsAgain() { log.calls.append("learnAgain") }
    func requestPermission(_ permission: Permission) { log.calls.append("warning \(permission.grantTitle)") }
    func finishWelcome() { log.calls.append("finishWelcome") }
    func refreshDiagnostics() { log.calls.append("refreshDiagnostics") }
    func menuWillOpen() { log.calls.append("menuWillOpen") }
    func reopenAutoHush() { log.calls.append("reopen") }
    func openSettings(page: SettingsWindowController.Page?) { log.calls.append(page.map { "\($0)" } ?? "settings") }
    func showControlError() { log.calls.append("why") }
    func openNotificationSettings() { log.calls.append("notificationSettings") }
    func quit() { log.calls.append("quit") }
}

/// Stands in for the updates' commands: each call is logged.
@MainActor
final class FakeUpdateCommands: UpdateCommands {
    let log: CallLog
    init(log: CallLog = CallLog()) { self.log = log }

    func checkFromUser() { log.calls.append("checkUpdates") }
    func presentAvailableUpdate() { log.calls.append("update") }
    func setChecksAutomatically(_ enabled: Bool) { log.calls.append("autoUpdate \(enabled)") }
    func setMode(_ mode: AutomaticUpdates) { log.calls.append("updates \(mode.rawValue)") }
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
