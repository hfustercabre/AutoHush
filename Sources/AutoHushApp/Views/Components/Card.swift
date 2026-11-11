import SwiftUI

extension EnvironmentValues {
    /// Inside Settings' pages, built as macOS's grouped forms
    /// (`SettingsPageScroll`): there a `Card` is the form's section.
    @Entry var cardsAreFormSections = false
    /// The title of the card a view is in, for its footer's Restore
    /// Defaults to name (I3, the user, 2026-10-27).
    @Entry var cardTitle: Text?
}

/// A group of controls, drawn by macOS (the user, 2026-10-17: "use the same
/// that macOS is using"): in Settings, a section of macOS's grouped form,
/// its title (and note) over it and its footer under it, as System
/// Settings' are; in the other windows, macOS's group box; the menu's card,
/// clear Liquid Glass from macOS 26 (`clearGlass`).
struct Card<Content: View, Footer: View>: View {
    /// Increase Contrast in light mode draws the menu card's clear glass
    /// dark under its black text, at 2.3:1: the glass is tinted white then
    /// (W1d, the WCAG audit's W1, the user's pick, 2026-11-11: 5.9:1).
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    var title: Text?
    /// A badge after the title, e.g. "Experimental".
    var badge: String?
    /// What the group is, under its title.
    var note: Text?
    /// A header of its own instead of a title: Diagnostics' folding parts,
    /// Sound Sources' sort and search.
    var heading: AnyView?
    /// The menu's card: clear Liquid Glass from macOS 26 over the panel's
    /// own glass, with no shadow; a faint fill before.
    var clearGlass = false
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer
    @Environment(\.cardsAreFormSections) private var isFormSection
    /// The menu's card is highlighted: the tint over its glass, under its content.
    @Environment(\.showsKeyHighlight) private var isHighlighted
    @Environment(\.keyHighlightByKeys) private var isHighlightedByKeys
    /// Its rows and footer, as one group for the arrow keys' highlight.
    @State private var highlightGroup = UUID()

    init(_ title: Text? = nil, badge: String? = nil, note: Text? = nil, heading: AnyView? = nil,
         clearGlass: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.badge = badge
        self.note = note
        self.heading = heading
        self.clearGlass = clearGlass
        self.content = content()
        self.footer = footer()
    }

    @ViewBuilder var body: some View {
        if isFormSection {
            Section { content } header: { header } footer: { footer }
                .environment(\.highlightGroup, highlightGroup)
                .environment(\.cardTitle, title)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                header.font(.appHeadline).padding(.leading, 4)
                box
                footer
            }
            .environment(\.highlightGroup, highlightGroup)
            .environment(\.cardTitle, title)
        }
    }

    /// The title, its badge and the note under them; nothing without them.
    @ViewBuilder private var header: some View {
        if let heading {
            heading.textCase(nil)
        } else if title != nil || note != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    HStack(spacing: 6) {
                        title
                        if let badge { HeadingBadge(text: badge) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
                if let note {
                    note.font(.appCaption).fontWeight(.regular).foregroundStyle(.appSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textCase(nil)
        }
    }

    @ViewBuilder private var box: some View {
        if #available(macOS 26, *), clearGlass {
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { highlight }
                .glassEffect(contrast == .increased && colorScheme == .light ? .clear.tint(.white.opacity(0.7)) : .clear,
                             in: RoundedRectangle(cornerRadius: ClearGlassCard.cornerRadius, style: .continuous))
        } else if clearGlass {
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { highlight }
                .background(RoundedRectangle(cornerRadius: ClearGlassCard.cornerRadius).fill(.quaternary.opacity(0.6)))
        } else {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The menu's card (`Card`'s `clearGlass`).
enum ClearGlassCard {
    /// Its corners: Liquid Glass's from macOS 26, a faint fill's before.
    static var cornerRadius: CGFloat {
        if #available(macOS 26, *) { 18 } else { 12 }
    }
}

extension Card {
    /// The menu's tint over the card's glass while it's highlighted.
    @ViewBuilder fileprivate var highlight: some View {
        if isHighlighted {
            HighlightTint(isFocused: true, byKeys: isHighlightedByKeys, cornerRadius: ClearGlassCard.cornerRadius,
                          fill: .cardFocusTint)
        }
    }
}

extension Card where Footer == EmptyView {
    init(_ title: Text? = nil, badge: String? = nil, note: Text? = nil, heading: AnyView? = nil,
         clearGlass: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(title, badge: badge, note: note, heading: heading, clearGlass: clearGlass,
                  content: content, footer: { EmptyView() })
    }
}

/// The line between two rows of a card; a form draws its own.
struct CardDivider: View {
    @Environment(\.cardsAreFormSections) private var isFormSection

    var body: some View {
        if !isFormSection { Divider().opacity(0.5) }
    }
}
