import Foundation

/// What the user decided about AutoHush's notifications.
enum NotificationPermission: Equatable, Sendable {
    /// Not asked yet, or asked with no answer yet. Reset Notifications… in
    /// System Settings brings AutoHush back here, so it can ask again.
    case notAsked
    case allowed
    /// The user turned notifications off.
    case off
}
