import SwiftUI

extension View {
    /// A text that may be cut short (a long player name) gets `full` as its
    /// help tag, only while it's cut (D-8 of 11-11, the user, 2026-11-17):
    /// an uncut copy, hidden behind it at the same width, is taller then.
    /// `when` false leaves the help tag to the control around it (a row's
    /// reason).
    /// `font` is the text's own, when set on it rather than around it.
    func truncationHelp(_ full: String, font: Font? = nil, when shown: Bool = true) -> some View {
        modifier(TruncationHelp(full: full, font: font, shown: shown))
    }
}

private struct TruncationHelp: ViewModifier {
    let full: String
    let font: Font?
    let shown: Bool
    @Environment(\.font) private var around
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if shown { measured(content) } else { content }
    }

    private func measured(_ content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
            .background(alignment: .topLeading) {
                Text(verbatim: full)
                    .font(font ?? around)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            }
            .help(isCut ? Text(verbatim: full) : Text(verbatim: ""))
            // For a disabled control around it, whose help tags don't show
            // from inside (`cutTextHelp`).
            .preference(key: CutTextKey.self, value: isCut ? full : nil)
    }

    private var isCut: Bool { fullHeight > shownHeight + 0.5 }
}

/// The whole text of a name cut short inside a view (`truncationHelp`).
private struct CutTextKey: PreferenceKey {
    static let defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) { value = value ?? nextValue() }
}

extension View {
    /// A disabled control (a tile not installed) shows the whole name cut
    /// short inside it as a help tag from outside, where SwiftUI shows help
    /// tags (R5 of 2026-11-17's diff review).
    func cutTextHelp() -> some View {
        overlayPreferenceValue(CutTextKey.self) { cut in
            if let cut { Color.clear.contentShape(Rectangle()).help(Text(verbatim: cut)) }
        }
    }
}
