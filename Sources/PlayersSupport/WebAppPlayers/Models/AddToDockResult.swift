import Foundation

/// How Safari's Add to Dock dialog ended.
package enum AddToDockResult: Equatable, Sendable {
    /// It didn't open: Safari's menu item or its dialog wasn't there.
    case unavailable
    /// The user closed it, with Add or with Cancel: the new web app, or none,
    /// tells which.
    case closed
    /// The add was cancelled in AutoHush meanwhile: the dialog was cancelled.
    case cancelled
}
