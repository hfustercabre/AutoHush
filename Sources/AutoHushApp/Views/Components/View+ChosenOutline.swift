import SwiftUI

extension View {
    /// The chosen look (STYLE_GUIDE's "Marking the chosen item"): while
    /// chosen, on macOS's selection color (`.listSelectionFill`, its text
    /// white: the view's), its corners 10 pt, with no outline, so it's never
    /// taken for the keys' highlight; where that is, outlined inside in
    /// white (2 pt), as a selected list row (S1, the user's pick,
    /// 2026-11-02: a player's tile; Add an App's choice cards since KB2a,
    /// the a11y audit's KB2, the user's pick, 2026-11-06: their accent tint
    /// and outline were the keys' look). `outlinedOtherwise`: in
    /// `.separator` (1 pt) while it isn't, unless the keys' highlight
    /// outlines it (a choice card). Clicks land anywhere inside it.
    func chosenOutline(_ isChosen: Bool, outlinedOtherwise: Bool = false) -> some View {
        modifier(ChosenOutline(isChosen: isChosen, outlinedOtherwise: outlinedOtherwise))
    }
}

/// `chosenOutline(_:outlinedOtherwise:)`.
private struct ChosenOutline: ViewModifier {
    let isChosen: Bool
    let outlinedOtherwise: Bool
    @Environment(\.keyHighlightByKeys) private var byKeys

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        content
            .background {
                if isChosen { shape.fill(Color.listSelectionFill) }
            }
            .overlay {
                if isChosen {
                    if byKeys { shape.strokeBorder(.onSelection, lineWidth: 2) }
                } else if outlinedOtherwise, !byKeys {
                    shape.strokeBorder(.separator, lineWidth: 1)
                }
            }
            .contentShape(shape)
    }
}
