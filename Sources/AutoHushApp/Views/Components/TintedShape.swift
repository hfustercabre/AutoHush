import SwiftUI

/// A shape filled with one of AutoHush's faint tints (a selection, a
/// warning's or a step's ground), outlined 1 pt in `outline` too while
/// Increase Contrast is on: a faint fill alone barely shows then (A9a, the
/// user's pick, 2026-11-01).
struct TintedShape<S: InsettableShape, Fill: ShapeStyle, Outline: ShapeStyle>: View {
    let shape: S
    let fill: Fill
    let outline: Outline
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        shape
            .fill(fill)
            .overlay { if contrast == .increased { shape.strokeBorder(outline, lineWidth: 1) } }
    }
}

extension InsettableShape {
    /// The shape on `fill`, outlined in `outline` with Increase Contrast (`TintedShape`).
    func tinted(_ fill: some ShapeStyle, outline: some ShapeStyle) -> some View {
        TintedShape(shape: self, fill: fill, outline: outline)
    }
}
