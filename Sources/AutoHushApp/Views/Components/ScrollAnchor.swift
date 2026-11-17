import AppKit
import SwiftUI

/// Marks where a page can be scrolled to (`ScrollDriver`): a Fine-Tuning
/// card a Behavior row asks for. As the background of the card's first row.
struct ScrollAnchor: NSViewRepresentable {
    let id: AnyHashable

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Self.keep(view, for: id)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        Self.keep(view, for: id)
    }

    /// The view of the anchor `id` that `accept` takes (in a given scroll
    /// view or window), while its row is made. Each window's anchor is kept:
    /// another one open at the same card (tests run windows at once) never
    /// takes its place (B-6 of 11-11).
    @MainActor static func view(for id: AnyHashable, where accept: (NSView) -> Bool = { _ in true }) -> NSView? {
        made[id]?.lazy.compactMap(\.view).first(where: accept)
    }

    @MainActor private static func keep(_ view: NSView, for id: AnyHashable) {
        var views = (made[id] ?? []).filter { $0.view != nil && $0.view !== view }
        views.append(WeakView(view))
        made[id] = views
    }

    /// The anchors made, by id; each kept weakly, as its row may go.
    @MainActor private static var made: [AnyHashable: [WeakView]] = [:]
}

private struct WeakView {
    weak var view: NSView?
    init(_ view: NSView) { self.view = view }
}
