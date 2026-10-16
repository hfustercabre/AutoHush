import SwiftUI

/// The text sizes of the menu, Settings and the welcome window: one step
/// above the system's, so descriptions and labels read easily.
extension Font {
    /// The app's name in Settings → About.
    static let appLargeTitle = Font.system(size: 24, weight: .bold)
    /// Plain text and rows' titles.
    static let appBody = Font.system(size: 14)
    /// A card's title, e.g. the media player's name.
    static let appHeadline = Font.system(size: 14, weight: .bold)
    /// Buttons, values and notes.
    static let appCallout = Font.system(size: 13)
    /// The line under the card's title: what's happening.
    static let appSubheadline = Font.system(size: 12)
    /// Descriptions under rows, section labels and captions.
    static let appCaption = Font.system(size: 11)
    /// A page's name in Settings' sidebar.
    static let appSidebarRow = Font.system(size: 16)
    /// AutoHush's name at the foot of Settings' sidebar.
    static let appSidebarName = Font.system(size: 15, weight: .semibold)
}
