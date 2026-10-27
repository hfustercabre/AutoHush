import SwiftUI

/// What scrolls in the menu, between its card and its buttons, and in its
/// side window: its content at its own height, scrolling only while the
/// screen caps the window (`isCapped`), its last rows then fading out over
/// a small chevron while more is below (C4, the user's pick, 2026-10-18;
/// the chevron alone before macOS 26). The arrow keys' highlight
/// (`revealed`) scrolls into view. Its scroll position is its own, so
/// scrolling redraws it alone, not the whole menu (the full check,
/// 2026-10-18). It reports its content's height (`onHeight`).
struct MenuScrollArea<Content: View>: View {
    let isCapped: Bool
    let revealed: UUID?
    let onHeight: @MainActor (CGFloat) -> Void
    @ViewBuilder let content: Content

    /// How far down the content shows, while it's taller than the window
    /// leaves (`nil` until it's measured).
    @State private var reach: ScrollReach?
    /// More is below the bottom edge: only while the screen caps the window,
    /// not while it grows (`StatusMenuModel.isCappedByScreen`).
    private var moreBelow: Bool { isCapped && reach?.moreBelow == true }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                content
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
                    // The rows themselves fade out at the bottom edge, so the
                    // window's own material shows through (the user, 2026-10-18).
                    .fadesOutBelow(reach, moreBelow: moreBelow)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            .showsMoreBelow($reach, moreBelow: moreBelow)
            .onChange(of: revealed) { _, revealed in
                if let revealed { scroller.scrollTo(revealed) }
            }
        }
    }

}
