import SwiftUI

extension View {
    /// The chosen look (STYLE_GUIDE's "Marking the chosen item"): while
    /// chosen, on `.selectedTileFill` and outlined in the accent color
    /// (2 pt), its corners 10 pt, so its whole name fits without a check:
    /// a player's tile, Add an App's choice cards. `outlinedOtherwise`: in
    /// `.separator` (1 pt) while it isn't (a choice card). Clicks land
    /// anywhere inside it.
    func chosenOutline(_ isChosen: Bool, outlinedOtherwise: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return background {
            if isChosen { shape.fill(.selectedTileFill) }
        }
        .overlay {
            if isChosen {
                shape.strokeBorder(Color.accentColor, lineWidth: 2)
            } else if outlinedOtherwise {
                shape.strokeBorder(.separator, lineWidth: 1)
            }
        }
        .contentShape(shape)
    }
}
