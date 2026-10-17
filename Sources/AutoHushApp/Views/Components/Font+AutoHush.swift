import SwiftUI

/// The text sizes of the menu, Settings and the other windows: macOS's own
/// text styles (the user, 2026-10-17: "native sizes and style text"), named
/// for what they're used for. Settings' sidebar keeps its larger names.
extension Font {
    /// The app's name in Settings → About.
    static let appLargeTitle = Font.largeTitle
    /// Plain text and rows' titles.
    static let appBody = Font.body
    /// A card's title, e.g. the media player's name; Settings' section titles.
    static let appHeadline = Font.headline
    /// Buttons, values and notes.
    static let appCallout = Font.callout
    /// The line under the card's title: what's happening.
    static let appSubheadline = Font.subheadline
    /// Descriptions under rows and captions, as System Settings' (11 pt).
    static let appCaption = Font.subheadline
    /// A page's name in Settings' sidebar.
    static let appSidebarRow = Font.system(size: 16)
    /// AutoHush's name at the foot of Settings' sidebar.
    static let appSidebarName = Font.system(size: 15, weight: .semibold)
}
