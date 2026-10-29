import Foundation
import AutoHushKit

/// What Settings and the menu ask of the updates (`UpdateController`), and
/// what Settings shows of them, read-only: the controller is observable, so
/// Settings follows it as it changes.
@MainActor
protocol UpdateCommands: AnyObject {
    /// Checks now, as asked from Settings.
    func checkFromUser()
    /// Checks now, as asked from the menu, and returns once it's done (its
    /// result shown).
    func checkNow() async
    /// Shows the update found (the menu's Install row).
    func presentAvailableUpdate()
    /// Checks by itself once a day, or not.
    func setChecksAutomatically(_ enabled: Bool)
    /// What automatic checks lead to: notify, download or install.
    func setMode(_ mode: AutomaticUpdates)
    /// Whether checks look for release candidates too.
    func setGetsReleaseCandidates(_ enabled: Bool)

    /// This copy's version; `nil` when unknown.
    var currentVersion: AppVersion? { get }
    /// Whether it checks by itself once a day.
    var checksAutomatically: Bool { get }
    /// What automatic checks lead to.
    var mode: AutomaticUpdates { get }
    /// Whether checks look for release candidates too.
    var getsReleaseCandidates: Bool { get }
    /// The update the last check found, if any.
    var availableUpdate: AppRelease? { get }
    /// Why this copy of AutoHush can't install updates, or nil when it can.
    var installUnavailability: UpdateInstallUnavailability? { get }
    /// The last check's, download's or install's outcome in one line, e.g.
    /// "Checking…"; `nil` before any.
    var status: String? { get }
    /// When updates were last checked for, by hand or automatically.
    var lastCheck: Date? { get }
    /// The user turned AutoHush's notifications off in System Settings.
    var notificationsOff: Bool { get }
}
