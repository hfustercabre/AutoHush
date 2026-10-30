import SwiftUI

/// A word in a capsule after a heading that qualifies everything under it,
/// e.g. "Experimental" after "Safari Web Apps"; in the accent color for a
/// good word ("Recommended", Add an App's ways), in macOS's own colors.
struct HeadingBadge: View {
    /// Already localized.
    let text: String
    var accent = false

    var body: some View {
        Text(verbatim: text)
            .font(.appCaption.weight(.semibold))
            .foregroundStyle(accent ? AnyShapeStyle(.appAccent) : AnyShapeStyle(.appWarning))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(accent ? AnyShapeStyle(.selectedRowFill) : AnyShapeStyle(.warningBadgeFill)))
            .fixedSize()
    }
}
