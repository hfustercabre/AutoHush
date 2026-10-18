import SwiftUI

/// A menu part's row that opens a side window beside the menu, as a
/// submenu's item does (W2, the user's pick, 2026-10-18), laid out as the
/// settings' switch rows: a picture 22 pt wide (wider for a stack of icons),
/// the title and a few words under it, and a chevron pointing to the side
/// where a switch would be; lit while its side window is open. Resting the
/// pointer on it opens it too (`onHover`, the user, 2026-10-18). It reports
/// where its top is, so the side window opens level with it.
struct MenuSideRow<Leading: View>: View {
    let title: String
    let subtitle: String?
    var leadingWidth = MenuSpacing.row.picture
    let isOpen: Bool
    let action: () -> Void
    /// The pointer came onto it (`true`) or left it.
    let onHover: (Bool) -> Void
    /// Its top in the menu's content (from the content's top, scrolled).
    let onTop: (CGFloat) -> Void
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuSpacing.row.gap) {
                leading()
                    .frame(width: leadingWidth, alignment: .leading)
                    .accessibilityHidden(true)
                // On one line, or two when it doesn't fit (long names: Ignored
                // Apps' count stays whole, the full check, 2026-10-18).
                ViewThatFits(in: .horizontal) {
                    RowTitle(Text(verbatim: title), subtitle: subtitle.map { Text(verbatim: $0) })
                        .lineLimit(1)
                    RowTitle(Text(verbatim: title), subtitle: subtitle.map { Text(verbatim: $0) })
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                // Toward the side window, mirrored right to left.
                Image(systemName: "chevron.forward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.appSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.leading, MenuSpacing.row.leading)
            .padding(.trailing, 16)
            .padding(.vertical, MenuSpacing.rowVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Tinted under the pointer, with the focus, and while its side window is open.
        .modifier(HighlightableControl(inset: 8, isLit: isOpen, press: action, opensSide: true))
        .onHover { onHover($0) }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { onTop($0) }
        .accessibilityValue(isOpen ? AccessibilityText.expanded : AccessibilityText.collapsed)
    }
}
