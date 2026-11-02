import AppKit
import SwiftUI

extension View {
    /// Announces the step to do now whenever it changes, so VoiceOver users
    /// hear the checklist move on. The windows' checklists announce. `atOnce`
    /// also announces it as the window appears: a locked window says why.
    /// At once, not after a delay: VoiceOver skips an announcement from
    /// AutoHush once another app is in front, as the web app's window is a
    /// second after Add a Web App's Continue (heard in the VM, 2026-10-19).
    func announcesCurrentStep(_ announcement: String?, atOnce: Bool = false) -> some View {
        onChange(of: announcement, initial: atOnce) { _, announcement in
            guard let announcement else { return }
            postStepAnnouncement(announcement)
        }
    }
}

/// Posts a step's announcement at high priority: the focus change that
/// comes with a step (Add a Web App's field dimmed, the web app's window
/// opening) would otherwise cut it off before VoiceOver says it (heard in the
/// VM, 2026-10-18). Through AppKit: SwiftUI's announcement keeps a priority
/// inside its text, not in the notification's priority, which VoiceOver reads.
@MainActor
func postStepAnnouncement(_ text: String) {
    postAnnouncement(text, priority: .high)
}

/// Posts an announcement at `priority`, through AppKit for the reason
/// above: a search's results go out at low priority, after what VoiceOver
/// is saying (2026-11-01).
@MainActor
func postAnnouncement(_ text: String, priority: NSAccessibilityPriorityLevel) {
    let element: NSObject = NSApp.keyWindow ?? NSApp
    NSAccessibility.post(element: element, notification: .announcementRequested, userInfo: announcementInfo(text, priority: priority))
}

/// The announcement's text and its priority, as `NSAccessibility` takes them.
func announcementInfo(_ text: String, priority: NSAccessibilityPriorityLevel) -> [NSAccessibility.NotificationUserInfoKey: Any] {
    [.announcement: text, .priority: priority.rawValue]
}
