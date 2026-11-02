import SwiftUI

extension View {
    /// The chosen look (STYLE_GUIDE's "Marking the chosen item"): while
    /// chosen, on `.selectedTileFill` and outlined in the accent color
    /// (2 pt), its corners 10 pt, so its whole name fits without a check:
    /// Add an App's choice cards. `solid`: on macOS's selection color
    /// instead (`.listSelectionFill`, its text white: the view's), with no
    /// outline, so it's never taken for the keys' highlight; where that is,
    /// outlined inside in white, as a selected list row (S1, the user's
    /// pick, 2026-11-02: a player's tile). `outlinedOtherwise`: in
    /// `.separator` (1 pt) while it isn't (a choice card). Clicks land
    /// anywhere inside it.
    func chosenOutline(_ isChosen: Bool, solid: Bool = false, outlinedOtherwise: Bool = false) -> some View {
        modifier(ChosenOutline(isChosen: isChosen, solid: solid, outlinedOtherwise: outlinedOtherwise))
    }
}

/// `chosenOutline(_:solid:outlinedOtherwise:)`.
private struct ChosenOutline: ViewModifier {
    let isChosen: Bool
    let solid: Bool
    let outlinedOtherwise: Bool
    @Environment(\.keyHighlightByKeys) private var byKeys

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        content
            .background {
                if isChosen { shape.fill(solid ? Color.listSelectionFill : .selectedTileFill) }
            }
            .overlay {
                if isChosen && solid {
                    if byKeys { shape.strokeBorder(.white, lineWidth: 2) }
                } else if isChosen {
                    shape.strokeBorder(Color.accentColor, lineWidth: 2)
                } else if outlinedOtherwise {
                    shape.strokeBorder(.separator, lineWidth: 1)
                }
            }
            .contentShape(shape)
    }
}
