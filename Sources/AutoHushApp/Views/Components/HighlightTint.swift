import SwiftUI

/// The tint itself (`focusTint`), behind a control or a row that is
/// highlighted or has the keyboard's focus; outlined in the accent color
/// (2 pt) where the keys put it, and always with Increase Contrast (A2a,
/// 2026-11-01): the accent the user picked, as macOS's focus ring, so at
/// 3:1 with some accents only in light mode (D5a, the a11y audit's D5,
/// 2026-11-06). Under the pointer, the tint alone.
/// `ring`: around a filled control (a prominent button), which hides what's
/// behind it, the outline alone, drawn out of it as macOS's focus ring
/// (P1, the user's pick, 2026-11-02); nothing under the pointer.
struct HighlightTint: View {
    let isFocused: Bool
    var byKeys = false
    var cornerRadius: CGFloat = 8
    var inset: CGFloat = 0
    var ring = false
    var fill: Color = .focusTint
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if isFocused, ring {
            if byKeys || contrast == .increased {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        } else if isFocused {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            shape
                .fill(fill)
                .overlay {
                    if byKeys || contrast == .increased { shape.strokeBorder(Color.accentColor, lineWidth: 2) }
                }
                .padding(.horizontal, inset)
                .allowsHitTesting(false)
        }
    }
}
