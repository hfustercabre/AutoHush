import SwiftUI

/// A word in a capsule after a heading that qualifies everything under it,
/// e.g. "Experimental" after "Safari Web Apps"; in the accent color for a
/// good word ("Recommended", Add an App's ways), in macOS's own colors.
/// `onSelection`: white, on a chosen tile's selection color (S1).
struct HeadingBadge: View {
    /// Already localized.
    let text: String
    var accent = false
    var onSelection = false

    var body: some View {
        let color = onSelection ? AnyShapeStyle(.white) : accent ? AnyShapeStyle(.appAccent) : AnyShapeStyle(.appWarning)
        let fill = onSelection ? AnyShapeStyle(.white.opacity(0.2))
            : accent ? AnyShapeStyle(.selectedRowFill) : AnyShapeStyle(.warningBadgeFill)
        Text(verbatim: text)
            .font(.appCaption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().tinted(fill, outline: color))
            .fixedSize()
    }
}
