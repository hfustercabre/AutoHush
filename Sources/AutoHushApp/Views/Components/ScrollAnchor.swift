import AppKit
import SwiftUI

/// Marks where a page can be scrolled to (`ScrollDriver`): a Fine-Tuning
/// card a Behavior row asks for. As the background of the card's first row.
struct ScrollAnchor: NSViewRepresentable {
    let id: AnyHashable

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Self.made[id] = WeakView(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        Self.made[id] = WeakView(view)
    }

    /// The view of the anchor `id`, while its row is made.
    @MainActor static func view(for id: AnyHashable) -> NSView? { made[id]?.view }

    /// The anchors made, by id; each kept weakly, as its row may go.
    @MainActor private static var made: [AnyHashable: WeakView] = [:]
}

private struct WeakView {
    weak var view: NSView?
    init(_ view: NSView) { self.view = view }
}
