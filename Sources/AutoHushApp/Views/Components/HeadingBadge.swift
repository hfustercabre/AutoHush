import SwiftUI

/// A word in a capsule after a heading that qualifies everything under it,
/// e.g. "Experimental" after "Safari Web Apps"; on the accent color's tint
/// for a good word ("Recommended", Add an App's ways), in macOS's own colors.
/// The good word itself in the primary color, outlined in the accent with
/// Increase Contrast (D5a, the a11y audit's D5, the user's pick, 2026-11-06:
/// accent words on the accent's tint read at about 2.4:1 in light mode).
/// `onSelection`: white, on a chosen tile's or card's selection color (S1).
struct HeadingBadge: View {
    /// Already localized.
    let text: String
    var accent = false
    var onSelection = false

    var body: some View {
        let color = onSelection ? AnyShapeStyle(.onSelection) : accent ? AnyShapeStyle(.appAccent) : AnyShapeStyle(.appWarning)
        let words = !onSelection && accent ? AnyShapeStyle(.primary) : color
        let fill = onSelection ? AnyShapeStyle(.onSelection.opacity(0.2))
            : accent ? AnyShapeStyle(.selectedRowFill) : AnyShapeStyle(.warningBadgeFill)
        Text(verbatim: text)
            .font(.appCaption.weight(.semibold))
            .foregroundStyle(words)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().tinted(fill, outline: color))
            .fixedSize()
    }
}
