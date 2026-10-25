import AppKit
import SwiftUI

/// Marks where a page can be scrolled to (`ScrollDriver`): a Fine-Tuning
/// card a Behavior row asks for. As the background of the card's first row.
struct ScrollAnchor: NSViewRepresentable {
    let id: AnyHashable

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchorViews[id] = WeakView(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchorViews[id] = WeakView(view)
    }
}

/// Scrolls the page it's in, once each time `target` is set, so that the
/// `ScrollAnchor` with that id shows at the top, its section's heading over
/// it. As the background of the page's first row, which is always there:
/// a grouped form makes its rows only as they come near the view, and
/// `ScrollViewReader` can't reach them at all (2026-10-25: its `scrollTo`
/// ran and nothing moved). A card not made yet is reached by going to the
/// page's end first, where the last cards are made.
struct ScrollDriver: NSViewRepresentable {
    let target: AnyHashable?
    /// Once it has scrolled: the request is done, so a row made again later
    /// (the form makes them as they come near) doesn't scroll back.
    let onScrolled: @MainActor () -> Void
    /// Room left above the anchor for its section's heading.
    private let headingRoom: CGFloat = 44

    final class Coordinator {
        var scrolledTo: AnyHashable?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard let target else {
            context.coordinator.scrolledTo = nil
            return
        }
        guard context.coordinator.scrolledTo != target else { return }
        context.coordinator.scrolledTo = target
        let room = headingRoom, done = onScrolled
        // Once the form has laid out its rows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let scroll = view.enclosingScrollView else { return }
            if Self.scroll(scroll, to: target, room: room) { return done() }
            Self.setOrigin(Self.end(of: scroll), of: scroll, animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                _ = Self.scroll(scroll, to: target, room: room)
                done()
            }
        }
    }

    /// Scrolls to the anchor `id`, if it's made and in this scroll view.
    @MainActor private static func scroll(_ scroll: NSScrollView, to id: AnyHashable, room: CGFloat) -> Bool {
        guard let anchor = anchorViews[id]?.view, anchor.enclosingScrollView === scroll,
              let document = scroll.documentView else { return false }
        let frame = anchor.convert(anchor.bounds, to: document)
        let visible = scroll.contentView.bounds.height
        let top = scroll.contentInsets.top + room
        let wanted = document.isFlipped ? frame.minY - top : frame.maxY + top - visible
        setOrigin(min(max(wanted, start(of: scroll)), end(of: scroll)), of: scroll, animated: true)
        return true
    }

    @MainActor private static func start(of scroll: NSScrollView) -> CGFloat {
        scroll.documentView?.isFlipped == false ? 0 : -scroll.contentInsets.top
    }

    @MainActor private static func end(of scroll: NSScrollView) -> CGFloat {
        max(start(of: scroll), (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
    }

    @MainActor private static func setOrigin(_ y: CGFloat, of scroll: NSScrollView, animated: Bool) {
        let origin = NSPoint(x: 0, y: y)
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                scroll.contentView.animator().setBoundsOrigin(origin)
            }
        } else {
            scroll.contentView.setBoundsOrigin(origin)
        }
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

/// The anchors made, by id; each kept weakly, as its row may go.
@MainActor private var anchorViews: [AnyHashable: WeakView] = [:]

private struct WeakView {
    weak var view: NSView?
    init(_ view: NSView) { self.view = view }
}
