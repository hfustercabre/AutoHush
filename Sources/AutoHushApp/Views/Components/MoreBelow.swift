import SwiftUI

/// The cue that more is below a scroll view's bottom edge: its content's
/// last `fadeHeight` fading out, over a small chevron. The menu's (C4) and
/// the welcome window's tiles' (U4, the user, 2026-10-20: "as the menu does").
enum MoreBelow {
    /// How tall the fade is at the bottom edge while more is below.
    static var fadeHeight: CGFloat { 32 }
    /// The content fades only from macOS 26: before, the mask takes the
    /// menu's vibrancy, every row dimmer while it's on (measured on 14.4 and
    /// 15, 2026-10-18), so the chevron alone says more is below.
    static var fadesRows: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    /// The content's mask: whole, but for its last `fadeHeight` above the
    /// bottom edge while more is below, which fades to clear. It goes in the
    /// content's own space (a mask on the scroll view doesn't reach
    /// AppKit's), so it moves with the scrolling to stay at the edge.
    @ViewBuilder static func mask(_ reach: ScrollReach?, moreBelow: Bool) -> some View {
        if let reach, moreBelow, fadesRows {
            VStack(spacing: 0) {
                Rectangle().frame(height: max(0, reach.visibleBottom - fadeHeight))
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: fadeHeight)
                Spacer(minLength: 0)
            }
        } else {
            Rectangle()
        }
    }

    /// A small chevron at the bottom edge, over the fading content: there's
    /// more below.
    static var chevron: some View {
        Image(systemName: "chevron.compact.down")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.appSecondary)
            .padding(.bottom, 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true) // VoiceOver reaches what's below by itself
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
struct MoreBelowReader: ViewModifier {
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

extension View {
    /// The scrolled content's part of the cue: where it is (macOS 14's
    /// `MoreBelowReader` reads it) and its fade at the bottom edge while
    /// more is below. With `showsMoreBelow` on its scroll view; the menu and
    /// the welcome window's tiles share both (R17, the full check, 2026-10-27).
    func fadesOutBelow(_ reach: ScrollReach?, moreBelow: Bool) -> some View {
        background { MoreBelowReader.contentFrame }
            .mask(alignment: .top) { MoreBelow.mask(reach, moreBelow: moreBelow) }
    }

    /// The scroll view's part of the cue: how far down its content shows,
    /// read into `reach`, and the chevron while more is below.
    func showsMoreBelow(_ reach: Binding<ScrollReach?>, moreBelow: Bool) -> some View {
        modifier(MoreBelowReader(reach: reach))
            .overlay(alignment: .bottom) {
                if moreBelow { MoreBelow.chevron.transition(.opacity) }
            }
            .animation(.easeOut(duration: 0.15), value: moreBelow)
    }
}
