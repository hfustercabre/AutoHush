import AppKit
import AutoHushKit
import UserNotifications

/// Shows update notifications and reports clicks on them.
/// `SystemUpdateNotifier` is the real one; tests stand in for it.
@MainActor
protocol UpdateNotifying: AnyObject {
    /// Called with the kind and version of a notification the user clicked.
    var onClick: (@MainActor (UpdateNotice.Kind, AppVersion) -> Void)? { get set }
    /// Starts receiving clicks. Called at launch, so a click that opened
    /// AutoHush reaches it too.
    func activate()
    /// Asks the user for permission to notify, unless they've already
    /// answered.
    func requestPermission()
    /// Shows `notice` in place of any earlier one, asking for permission when
    /// it hasn't been asked yet.
    func announce(_ notice: UpdateNotice)
    /// Removes the notification shown, which no longer applies.
    func withdraw()
    /// What the user decided about AutoHush's notifications, now.
    func permission() async -> NotificationPermission
}

/// Update notifications through the Notification Center. All of them share
/// one identifier, so a new one replaces the one before. The notification
/// center is touched only when used, so tests can build an `AppDelegate`.
@MainActor
final class SystemUpdateNotifier: NSObject, UpdateNotifying {
    var onClick: (@MainActor (UpdateNotice.Kind, AppVersion) -> Void)?

    private static let identifier = "update"
    private let logger = AutoHushLogger(category: "Updates")

    private var center: UNUserNotificationCenter { .current() }

    func activate() {
        center.delegate = self
    }

    func requestPermission() {
        let center = center
        Task {
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert])
        }
    }

    func announce(_ notice: UpdateNotice) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.userInfo = ["kind": notice.kind.rawValue, "version": notice.version.description]
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil)
        let center = center
        Task {
            let isAllowed = { (status: UNAuthorizationStatus) in status == .authorized || status == .provisional }
            let wasAsked = await center.notificationSettings().authorizationStatus != .notDetermined
            // Asks only the first time; afterwards it answers with the user's choice.
            _ = try? await center.requestAuthorization(options: [.alert])
            var status = await center.notificationSettings().authorizationStatus
            // When this request asked, macOS can answer "not allowed" before the
            // user has chosen (when the prompt's banner goes away) and record
            // their "Allow" later, from Notification Center: wait for it a while.
            if !wasAsked {
                for _ in 0..<300 where !isAllowed(status) {
                    try? await Task.sleep(for: .seconds(1))
                    status = await center.notificationSettings().authorizationStatus
                }
            }
            guard isAllowed(status) else {
                logger.info("No notification for \(notice.key, privacy: .public): notifications are off")
                return
            }
            do {
                try await center.add(request)
                logger.info("Notified: \(notice.key, privacy: .public)")
            } catch {
                logger.error("Couldn't notify: \(error)")
            }
        }
    }

    func withdraw() {
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }

    func permission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notAsked
        case .denied: .off
        default: .allowed
        }
    }
}

extension SystemUpdateNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let info = response.notification.request.content.userInfo
        guard let kind = (info["kind"] as? String).flatMap(UpdateNotice.Kind.init),
              let version = (info["version"] as? String).flatMap(AppVersion.init)
        else { return }
        await MainActor.run { onClick?(kind, version) }
    }

    /// Shows notifications as banners even while AutoHush is the active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
