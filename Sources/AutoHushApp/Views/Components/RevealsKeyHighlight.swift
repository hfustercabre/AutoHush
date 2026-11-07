import SwiftUI

/// Scrolls the arrow keys' highlight into view as it moves
/// (`KeyHighlight.revealed`): every Settings page, About's too (R7, the full
/// check, 2026-10-27: written on each before), and what scrolls in the menu
/// and its side window (`MenuScrollArea`), which scroll without animating;
/// none does with Reduce Motion on (A11, 2026-11-01), as the menu's panel
/// and `ScrollDriver` don't. Its height is the highlight's page
/// (`MeasuresHighlightPage`).
struct RevealsKeyHighlight: ViewModifier {
    let scroller: ScrollViewProxy
    var animated = true
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    func body(content: Content) -> some View {
        content.measuresHighlightPage().onChange(of: keyboard?.revealed) { _, revealed in
            guard let revealed else { return }
            if animated, !reducesMotion {
                withAnimation(.easeOut(duration: 0.15)) { scroller.scrollTo(revealed) }
            } else {
                scroller.scrollTo(revealed)
            }
        }
    }
}

/// What scrolls in a window with a highlight (`KeyHighlight`), its height
/// told as the highlight's page, for Page Up and Page Down
/// (`KeyHighlight.pageHeight`, 2026-11-01).
struct MeasuresHighlightPage: ViewModifier {
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { keyboard?.pageHeight = $0 }
    }
}

extension View {
    /// Tells the highlight how tall a page is (`MeasuresHighlightPage`).
    func measuresHighlightPage() -> some View {
        modifier(MeasuresHighlightPage())
    }

    /// Scrolls the arrow keys' highlight into view with `scroller` (`RevealsKeyHighlight`).
    func revealsKeyHighlight(with scroller: ScrollViewProxy, animated: Bool = true) -> some View {
        modifier(RevealsKeyHighlight(scroller: scroller, animated: animated))
    }
}
