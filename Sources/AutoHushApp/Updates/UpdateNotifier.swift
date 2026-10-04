import AppKit
import OSLog
import UserNotifications

/// Something about updates worth a notification.
enum UpdateNotice: Equatable, Sendable {
    /// A newer version is available ("Notify me").
    case available(AppVersion, running: AppVersion)
    /// A newer version is downloaded and ready ("Download it and notify me").
    case downloaded(AppVersion)
    /// AutoHush was updated to this version.
    case installed(AppVersion)
    /// Installing this version automatically failed.
    case installFailed(AppVersion)

    enum Kind: String, Sendable {
        case available, downloaded, installed, installFailed
    }

    var kind: Kind {
        switch self {
        case .available: .available
        case .downloaded: .downloaded
        case .installed: .installed
        case .installFailed: .installFailed
        }
    }

    var version: AppVersion {
        switch self {
        case .available(let version, _), .downloaded(let version), .installed(let version), .installFailed(let version):
            version
        }
    }

    /// E.g. "available 0.3.8": each notice is sent once.
    var key: String { "\(kind.rawValue) \(version)" }

    var title: String {
        let version = version.description
        switch self {
        case .available:
            return String(localized: "AutoHush \(version) is available",
                          comment: "Notification title; %@ is the new version")
        case .downloaded:
            return String(localized: "AutoHush \(version) is ready to install",
                          comment: "Notification title; %@ is the new version, already downloaded")
        case .installed:
            return String(localized: "AutoHush was updated to \(version)",
                          comment: "Notification title after an update; %@ is the version now running")
        case .installFailed:
            return String(localized: "Couldn't update AutoHush to \(version)",
                          comment: "Notification title; %@ is the version that failed to install")
        }
    }

    var body: String {
        switch self {
        case .available(_, let running):
            return String(localized: "You're running \(running.description). Click to see what's new and install it.",
                          comment: "Notification text; %@ is the installed version")
        case .downloaded:
            return String(localized: "It's downloaded. Click to see what's new and install it.",
                          comment: "Notification text for a downloaded update")
        case .installed:
            return String(localized: "Click to see what's new.", comment: "Notification text after an update")
        case .installFailed:
            return String(localized: "Click to try again, or to download it yourself.",
                          comment: "Notification text after an update failed to install")
        }
    }
}

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
    /// Whether the user turned AutoHush's notifications off.
    func notificationsAreOff() async -> Bool
}

/// Update notifications through the Notification Center. All of them share
/// one identifier, so a new one replaces the one before. The notification
/// center is touched only when used, so tests can build an `AppDelegate`.
@MainActor
final class SystemUpdateNotifier: NSObject, UpdateNotifying {
    var onClick: (@MainActor (UpdateNotice.Kind, AppVersion) -> Void)?

    private static let identifier = "update"
    private let logger = Logger(category: "Updates")

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
            guard isAllowed(status) else { return }
            do {
                try await center.add(request)
            } catch {
                logger.error("Couldn't notify: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func withdraw() {
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }

    func notificationsAreOff() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
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
