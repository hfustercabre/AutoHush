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
    /// What it asks of the Notification Center: the real one's calls, unless
    /// a test stands in for them.
    @MainActor
    struct Center {
        /// What the user decided about AutoHush's notifications.
        var status: @MainActor () async -> UNAuthorizationStatus
        /// Asks the user the first time; afterwards it answers with their choice.
        var requestAuthorization: @MainActor () async -> Void
        /// Shows `notice` in place of the one shown.
        var add: @MainActor (UpdateNotice) async throws -> Void
        /// Removes the notification shown, or about to be.
        var remove: @MainActor () -> Void
        /// Waits between looks at the permission.
        var sleep: @MainActor (Duration) async -> Void

        static var live: Center {
            Center(
                status: { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
                requestAuthorization: { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) },
                add: { notice in
                    let content = UNMutableNotificationContent()
                    content.title = notice.title
                    content.body = notice.body
                    content.userInfo = ["kind": notice.kind.rawValue, "version": notice.version.description]
                    try await UNUserNotificationCenter.current()
                        .add(UNNotificationRequest(identifier: SystemUpdateNotifier.identifier, content: content, trigger: nil))
                },
                remove: {
                    let center = UNUserNotificationCenter.current()
                    center.removeDeliveredNotifications(withIdentifiers: [SystemUpdateNotifier.identifier])
                    center.removePendingNotificationRequests(withIdentifiers: [SystemUpdateNotifier.identifier])
                },
                sleep: { try? await Task.sleep(for: $0) }
            )
        }
    }

    var onClick: (@MainActor (UpdateNotice.Kind, AppVersion) -> Void)?

    private static let identifier = "update"
    private let logger = AutoHushLogger(category: "Updates")
    private let center: Center
    /// The notice to show once AutoHush may: a later one takes its place,
    /// and a withdrawal drops it.
    private var waiting: UpdateNotice?
    /// Shows `waiting`, once the permission is known. One at a time, so two
    /// notices waiting for the prompt's answer can't race.
    private var showing: Task<Void, Never>?

    init(center: Center = .live) {
        self.center = center
    }

    func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        let center = center
        Task {
            guard await center.status() == .notDetermined else { return }
            await center.requestAuthorization()
        }
    }

    func announce(_ notice: UpdateNotice) {
        waiting = notice
        guard showing == nil else { return } // the one under way shows it
        showing = Task {
            let isAllowed = await mayNotify()
            // The latest notice announced meanwhile, if it wasn't withdrawn.
            while let notice = waiting {
                waiting = nil
                guard isAllowed else {
                    logger.info("No notification for \(notice.key, privacy: .public): notifications are off")
                    continue
                }
                do {
                    try await center.add(notice)
                    logger.info("Notified: \(notice.key, privacy: .public)")
                } catch {
                    logger.error("Couldn’t notify: \(error)")
                }
            }
            showing = nil
        }
    }

    /// Whether AutoHush may notify. Asks the first time, then waits a while
    /// for the user's answer.
    private func mayNotify() async -> Bool {
        let isAllowed = { (status: UNAuthorizationStatus) in status == .authorized || status == .provisional }
        let wasAsked = await center.status() != .notDetermined
        // Asks only the first time; afterwards it answers with the user's choice.
        await center.requestAuthorization()
        var status = await center.status()
        // When this request asked, macOS can answer "not allowed" before the
        // user has chosen (when the prompt's banner goes away) and record
        // their "Allow" later, from Notification Center: wait for it a while.
        if !wasAsked {
            for _ in 0..<300 where !isAllowed(status) {
                await center.sleep(.seconds(1))
                status = await center.status()
            }
        }
        return isAllowed(status)
    }

    func withdraw() {
        waiting = nil
        center.remove()
    }

    func permission() async -> NotificationPermission {
        switch await center.status() {
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
