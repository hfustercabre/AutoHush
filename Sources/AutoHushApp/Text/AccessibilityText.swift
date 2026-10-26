import SwiftUI

/// What VoiceOver says of a control that shows or hides what's under it or
/// beside it: Settings → Diagnostics' headings, the menu's parts' titles
/// that fold (Detection, Fades), and its rows that open a side window
/// (Media Player, Ignored Apps).
enum AccessibilityText {
    static var expanded: Text {
        Text("Expanded", comment: "VoiceOver: a heading or row while what it shows is open (Settings → Diagnostics' parts, the menu's Detection and Fades titles, the menu's Media Player and Ignored Apps rows while their side window is open); a click hides it")
    }

    static var collapsed: Text {
        Text("Collapsed", comment: "VoiceOver: a heading or row while what it shows is hidden (Settings → Diagnostics' parts, the menu's Detection and Fades titles, the menu's Media Player and Ignored Apps rows while their side window is closed); a click shows it")
    }
}
