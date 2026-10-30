import Foundation
import AutoHushKit
@testable import AutoHushApp
import AutoHushTestSupport

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
    func reopenAutoHush() -> Bool {
        log.calls.append("reopen")
        return true
    }
    func openSettings(page: SettingsPage?) { log.calls.append(page.map { "\($0)" } ?? "settings") }
    func showControlError() { log.calls.append("why") }
    func showLogs() { log.calls.append("showLogs") }
    func openNotificationSettings() { log.calls.append("notificationSettings") }
    func moveMenuBarIconNearSystemIcons() { log.calls.append("moveMenuBarIcon"); menuBarIconIsHidden = false }
    /// As the test sets it; moving the icon shows it.
    var menuBarIconIsHidden = false
    func quit() { log.calls.append("quit") }
}
