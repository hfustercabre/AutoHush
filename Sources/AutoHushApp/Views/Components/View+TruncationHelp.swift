import SwiftUI

extension View {
    /// A text that may be cut short (a long player name) gets `full` as its
    /// help tag, only while it's cut (D-8 of 11-11, the user, 2026-11-17):
    /// an uncut copy, hidden behind it at the same width, is taller then.
    /// `when` false leaves the help tag to the control around it (a row's
    /// reason).
    /// `font` is the text's own, when set on it rather than around it;
    /// `minimumScale` its `minimumScaleFactor`: a name that fits once shrunk
    /// isn't cut (the diff review's R4).
    func truncationHelp(_ full: String, font: Font? = nil, minimumScale: CGFloat = 1, when shown: Bool = true) -> some View {
        modifier(TruncationHelp(full: full, font: font, minimumScale: minimumScale, shown: shown))
    }
}

private struct TruncationHelp: ViewModifier {
    let full: String
    let font: Font?
    let minimumScale: CGFloat
    let shown: Bool
    @Environment(\.font) private var around
    @State private var shownSize: CGSize = .zero
    @State private var fullHeight: CGFloat = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if shown { measured(content) } else { content }
    }

    private func measured(_ content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { shownSize = $0 }
            .background(alignment: .topLeading) {
                // At full size in a width as much wider as it may shrink: it
                // wraps as the shrunk text would.
                Text(verbatim: full)
                    .font(font ?? around)
                    .lineLimit(nil)
                    .frame(width: shownSize.width / max(minimumScale, 0.1), alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            }
            // Also VoiceOver's help (SwiftUI sets both; a hint set to nothing
            // doesn't clear it, seen 2026-11-18): it then says the whole name
            // where its label may be shortened (R7, left).
            .help(isCut ? Text(verbatim: full) : Text(verbatim: ""))
            // For a disabled control around it, whose help tags don't show
            // from inside (`cutTextHelp`).
            .preference(key: CutTextKey.self, value: isCut ? full : nil)
    }

    private var isCut: Bool { shownSize.width > 0 && fullHeight * minimumScale > shownSize.height + 0.5 }
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
        modifier(CutTextHelp())
    }
}

/// `cutTextHelp`: the help tag on the control itself, as a dimmed tile's
/// reason is (no element of its own for VoiceOver).
private struct CutTextHelp: ViewModifier {
    @State private var cut: String?

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(CutTextKey.self) { cut = $0 }
            .help(cut.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
    }
}
