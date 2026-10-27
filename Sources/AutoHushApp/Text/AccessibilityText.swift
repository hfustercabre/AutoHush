import SwiftUI

/// What VoiceOver says of a control that shows or hides what's under it or
/// beside it: Settings → Diagnostics' headings, and the menu's rows that
/// open a side window (the card's Change Player, Ignored Apps).
enum AccessibilityText {
    static var expanded: Text {
        Text("Expanded", comment: "VoiceOver: a heading or row while what it shows is open (Settings → Diagnostics' parts, the menu card's Change Player row and the Ignored Apps row while their side window is open); a click hides it")
    }

    static var collapsed: Text {
        Text("Collapsed", comment: "VoiceOver: a heading or row while what it shows is hidden (Settings → Diagnostics' parts, the menu card's Change Player row and the Ignored Apps row while their side window is closed); a click shows it")
    }
}
