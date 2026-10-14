import SwiftUI

/// A group of controls on a rounded, tinted background: the menu's card,
/// and each group in Settings. On macOS 26 and later it's a Liquid Glass
/// panel, a little rounder and roomier.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    /// Clear glass, which casts no shadow: for a card whose view ends just
    /// under it, where the regular glass's shadow would be cut off in a
    /// straight line (the menu's card, in its row).
    var clearGlass = false
    @ViewBuilder let content: Content

    @ViewBuilder var body: some View {
        if #available(macOS 26, *) {
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(padding + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(clearGlass ? .clear : .regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.cardBorder, lineWidth: 1))
        }
    }
}

/// The line between two rows of a card.
struct CardDivider: View {
    var body: some View {
        Divider().opacity(0.5)
    }
}
