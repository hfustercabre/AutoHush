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
    /// How tall the rows' fade is at the bottom edge while more is below.
    static var fadeHeight: CGFloat { 32 }
    /// The rows fade only from macOS 26: before, the mask takes their
    /// vibrancy, every row dimmer while it's on (measured on 14.4 and 15,
    /// 2026-10-18), so the chevron alone says more is below.
    static var fadesRows: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                content
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
                    .background { MoreBelowReader.contentFrame }
                    // The rows themselves fade out at the bottom edge, so the
                    // window's own material shows through (the user, 2026-10-18).
                    .mask(alignment: .top) { fadeMask }
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            .modifier(MoreBelowReader(reach: $reach))
            .overlay(alignment: .bottom) {
                if moreBelow { moreBelowChevron.transition(.opacity) }
            }
            .animation(.easeOut(duration: 0.15), value: moreBelow)
            .onChange(of: revealed) { _, revealed in
                if let revealed { scroller.scrollTo(revealed) }
            }
        }
    }

    /// The rows' mask: whole, but for their last `fadeHeight` above the
    /// bottom edge while more is below, which fades to clear. It's in the
    /// rows' own space (a mask on the scroll view doesn't reach AppKit's),
    /// so it moves with the scrolling to stay at the edge.
    @ViewBuilder private var fadeMask: some View {
        if let reach, moreBelow, Self.fadesRows {
            VStack(spacing: 0) {
                Rectangle().frame(height: max(0, reach.visibleBottom - Self.fadeHeight))
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.fadeHeight)
                Spacer(minLength: 0)
            }
        } else {
            Rectangle()
        }
    }

    /// A small chevron at the bottom edge, over the fading rows: there's
    /// more below.
    private var moreBelowChevron: some View {
        Image(systemName: "chevron.compact.down")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.appSecondary)
            .padding(.bottom, 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true) // VoiceOver reaches the rows below by itself
    }
}

/// How far down a scroll view's content shows.
struct ScrollReach: Equatable {
    /// The bottom edge of what shows, in the content's own space.
    var visibleBottom: CGFloat
    var contentHeight: CGFloat
    var moreBelow: Bool { visibleBottom < contentHeight - 1 }
}

/// How far down a scroll view's content shows: from macOS 15 by its scroll
/// geometry; on macOS 14 by where its content is in it.
private struct MoreBelowReader: ViewModifier {
    @Binding var reach: ScrollReach?
    @State private var height: CGFloat = 0
    @State private var contentFrame: CGRect = .zero

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: ScrollReach.self) { geometry in
                ScrollReach(visibleBottom: geometry.contentOffset.y + geometry.containerSize.height,
                            contentHeight: geometry.contentSize.height)
            } action: { _, new in reach = new }
        } else {
            content
                .coordinateSpace(.named(Self.space))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0; update() }
                .onPreferenceChange(ContentFrame.self) { frame in
                    MainActor.assumeIsolated { contentFrame = frame ?? .zero; update() }
                }
        }
    }

    private func update() {
        reach = ScrollReach(visibleBottom: height - contentFrame.minY, contentHeight: contentFrame.height)
    }

    static let space = "menuScroll"

    /// Behind the scrolled content: where it is (macOS 14 only reads it).
    static var contentFrame: some View {
        GeometryReader { Color.clear.preference(key: ContentFrame.self, value: $0.frame(in: .named(space))) }
    }

    /// Where the scrolled content is, in the scroll view's own space. Views
    /// that don't set it give `nil`, which mustn't replace the frame (macOS
    /// 14 reduces them in after it: measured on 14.4, 2026-10-18).
    struct ContentFrame: PreferenceKey {
        static let defaultValue: CGRect? = nil
        static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
    }
}
