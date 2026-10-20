import SwiftUI

/// What differs between AutoHush's check panel and Player Check's: the
/// caption's size and two fills, each app's own. `CheckRequestNote` and
/// `CheckWindowStepView` draw the same with either.
package struct CheckPanelLook {
    package var caption: Font
    /// Behind what the check asks: orange, faint.
    package var warningFill: Color
    /// The window states not reached yet.
    package var track: Color

    package init(caption: Font, warningFill: Color, track: Color) {
        self.caption = caption
        self.warningFill = warningFill
        self.track = track
    }
}
