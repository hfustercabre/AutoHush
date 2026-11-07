import SwiftUI

/// In the menu and Settings (wherever a `KeyHighlight` is given), a control
/// that the arrow keys and the pointer highlight and the keyboard's focus
/// reaches, all three shown by a faint tint behind it (F5, the user's
/// pick, 2026-10-18; under the pointer too, the user: "the accent color
/// should show not only on keyboard navigation, but also when the mouse is
/// over the item"; macOS's faint grey since 2026-11-06, `.focusTint`),
/// instead of macOS's focus ring; outlined in the accent color where the
/// keys put it (`HighlightTint`).
/// For a control that is itself focusable (a button, a switch); a row that
/// holds one uses `Highlightable` with its control's focus. In a row that
/// takes the highlight for its control (`Highlightable.ownsControls`), only
/// its focus shows. Elsewhere, macOS's ring stays.
struct HighlightableControl: ViewModifier {
    var cornerRadius: CGFloat = 8
    /// How far in from the control's sides the tint is drawn.
    var inset: CGFloat = 0
    /// How far out around a control that fills its own frame (a switch).
    var outset: CGFloat = 0
    /// A ring `outset` out, not the tint behind it: a filled control
    /// (`HighlightTint.ring`).
    var ring = false
    /// Kept on: a row whose side window is open.
    var isLit = false
    /// A row that draws its tint itself (`MenuRowButtonStyle`), inside its
    /// own padding, instead of the tint behind it (`showsKeyHighlight`).
    var lightsItself = false
    /// What Return or Space does while it's highlighted.
    let press: (() -> Void)?
    var opensSide = false
    /// It stands for what's shown now (`KeyHighlight.Control.isCurrent`).
    var isCurrent: (() -> Bool)?
    /// Each change gives it the keyboard's focus (`StatusMenuModel.sideRowFocusRequests`).
    var focusRequests = 0
    @FocusState private var isFocused: Bool
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?
    @Environment(\.isInHighlightedRow) private var isInHighlightedRow

    @ViewBuilder func body(content: Content) -> some View {
        if let keyboard, isInHighlightedRow {
            content
                .focused($isFocused)
                .focusEffectDisabled()
                .background {
                    HighlightTint(isFocused: isFocused && !keyboard.hidesFocus, byKeys: true, cornerRadius: cornerRadius, inset: inset,
                                  ring: ring)
                        .padding(-outset)
                }
        } else if keyboard == nil {
            content
        } else {
            content
                .focused($isFocused)
                .focusEffectDisabled()
                .onChange(of: focusRequests) { isFocused = true }
                .modifier(Highlightable(isFocused: isFocused, cornerRadius: cornerRadius, inset: inset, outset: outset, ring: ring,
                                        isLit: isLit, lightsItself: lightsItself, press: press, opensSide: opensSide,
                                        isCurrent: isCurrent))
        }
    }
}
