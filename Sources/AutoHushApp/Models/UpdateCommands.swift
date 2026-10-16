import Foundation
import AutoHushKit

/// What Settings and the menu ask of the updates (`UpdateController`).
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
}
