import Foundation
@testable import AutoHushApp

/// Stands in for `SystemUpdateNotifier`: records the notifications it's asked
/// to show and withdraw.
@MainActor
final class MockUpdateNotifier: UpdateNotifying {
    var onClick: (@MainActor (UpdateNotice.Kind, AppVersion) -> Void)?
    private(set) var isActive = false
    private(set) var announced: [UpdateNotice] = []
    private(set) var withdrawals = 0
    /// Whether the user turned notifications off.
    var areOff = false

    func activate() { isActive = true }
    func announce(_ notice: UpdateNotice) { announced.append(notice) }
    func withdraw() { withdrawals += 1 }
    func notificationsAreOff() async -> Bool { areOff }

    /// Acts as if the user clicked a notification.
    func click(_ kind: UpdateNotice.Kind, _ version: String) {
        onClick?(kind, AppVersion(version)!)
    }
}
