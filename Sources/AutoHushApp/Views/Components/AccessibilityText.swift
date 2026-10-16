import SwiftUI

/// What VoiceOver says of a control that shows or hides what's under it:
/// Settings → Diagnostics' headings, the menu card's player button.
enum AccessibilityText {
    static var expanded: Text {
        Text("Expanded", comment: "VoiceOver: a heading or button while what's under it shows (Settings → Diagnostics' parts, the players under the menu's card); a click hides it")
    }

    static var collapsed: Text {
        Text("Collapsed", comment: "VoiceOver: a heading or button while what's under it is hidden (Settings → Diagnostics' parts, the players under the menu's card); a click shows it")
    }
}
