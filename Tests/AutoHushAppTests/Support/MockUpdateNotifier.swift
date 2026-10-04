import Foundation
@testable import AutoHushApp

/// Stands in for `SystemUpdateNotifier`: records the notifications it's asked
/// to show and withdraw.
@MainActor
final class MockUpdateNotifier: UpdateNotifying {
    var onClick: (@MainActor (UpdateNotice.Kind, AppVersion) -> Void)?
    private(set) var isActive = false
    private(set) var permissionRequests = 0
    private(set) var announced: [UpdateNotice] = []
    private(set) var withdrawals = 0
    /// What the user decided about notifications.
    var currentPermission = NotificationPermission.allowed

    func activate() { isActive = true }
    func requestPermission() { permissionRequests += 1 }
    func announce(_ notice: UpdateNotice) { announced.append(notice) }
    func withdraw() { withdrawals += 1 }
    func permission() async -> NotificationPermission { currentPermission }

    /// Acts as if the user clicked a notification.
    func click(_ kind: UpdateNotice.Kind, _ version: String) {
        onClick?(kind, AppVersion(version)!)
    }
}
