import SwiftUI

/// A menu part's row that folds what's under it (V5, the user's pick,
/// 2026-10-18), laid out as the settings' switch rows: a picture 22 pt wide
/// (wider for a stack of icons), the title and a few words under it, and a
/// chevron where a switch would be, pointing down while folded.
struct MenuFoldingRow<Leading: View>: View {
    let title: String
    let subtitle: String?
    var leadingWidth: CGFloat = 22
    let isOpen: Bool
    let action: () -> Void
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                leading()
                    .frame(width: leadingWidth, alignment: .leading)
                    .accessibilityHidden(true)
                RowTitle(Text(verbatim: title), subtitle: subtitle.map { Text(verbatim: $0) })
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.appSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOpen ? AccessibilityText.expanded : AccessibilityText.collapsed)
    }
}

/// A part's title in the menu ("Media Player", "Detection"), as the
/// settings' page names over their parts.
struct MenuPartTitle: View {
    let title: Text

    init(_ title: Text) { self.title = title }

    var body: some View {
        SectionLabel(title)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A title inside a menu part ("Modes", "Timing", "Supported Apps"): a
/// description's size, grey; the part's groups have no lines between them
/// (the user, 2026-10-18).
struct MenuInnerTitle: View {
    let title: Text

    init(_ title: Text) { self.title = title }

    var body: some View {
        title
            .font(.appCaption)
            .foregroundStyle(.appSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}
