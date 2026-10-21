import SwiftUI

/// What differs between AutoHush's check panel and Player Check's: the
/// caption's size, what the check asks in and behind it, and the track,
/// each app's own. `CheckRequestNote` and
/// `CheckWindowStepView` draw the same with either.
package struct CheckPanelLook {
    package var caption: Font
    /// What the check asks: its symbol and words.
    package var requestTint: Color
    /// Behind what the check asks: `requestTint`, faint.
    package var requestFill: Color
    /// The window states not reached yet.
    package var track: Color

    package init(caption: Font, requestTint: Color, requestFill: Color, track: Color) {
        self.caption = caption
        self.requestTint = requestTint
        self.requestFill = requestFill
        self.track = track
    }
}
