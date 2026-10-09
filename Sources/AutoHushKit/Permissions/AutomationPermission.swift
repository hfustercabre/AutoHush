import CoreServices
import Foundation

/// The Automation permission (Apple events) to control one running app.
package enum AutomationPermission: Equatable, Sendable {
    case allowed
    case denied
    /// macOS hasn't asked yet: asking shows its prompt.
    case notAsked
    /// The app isn't running any more (or any other answer).
    case notRunning

    /// What `AEDeterminePermissionToAutomateTarget` answered.
    package init(status: OSStatus) {
        switch status {
        case noErr: self = .allowed
        case OSStatus(errAEEventNotPermitted): self = .denied
        case OSStatus(errAEEventWouldRequireUserConsent): self = .notAsked
        default: self = .notRunning // procNotFound: it quit meanwhile
        }
    }

    /// Asks macOS whether AutoHush may send the app running as `pid` the
    /// standard "get data" event; with `ask`, macOS shows its prompt when it
    /// hasn't asked yet. It blocks (until the user answers, when asking):
    /// run it on a queue of its own (`DispatchQueue.run`).
    package static func check(pid: pid_t, ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), ask)
    }
}
