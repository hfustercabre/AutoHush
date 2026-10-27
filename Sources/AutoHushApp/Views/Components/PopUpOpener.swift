import AppKit
import SwiftUI

/// Opens a pop-up (a `Picker` in `.menu` style) from the keys: Return or
/// Space on the arrow keys' highlight, as on a pop-up with the keyboard's
/// focus (N2, the user, 2026-10-27: About's update pop-up ignored them).
/// SwiftUI can't open one itself: behind the pop-up (`opened(by:)`), it
/// finds the AppKit pop-up button drawn there and clicks it.
@MainActor
final class PopUpOpener {
    fileprivate weak var anchor: NSView?

    /// The pop-up button over the anchor, if AppKit draws one there.
    var popUpButton: NSPopUpButton? {
        guard let anchor, let content = anchor.window?.contentView else { return nil }
        let center = anchor.convert(NSPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: nil)
        var view = content.hitTest(center)
        while let found = view, !(found is NSPopUpButton) { view = found.superview }
        return view as? NSPopUpButton
    }

    /// Shows the pop-up's choices, as a click does.
    func open() { popUpButton?.performClick(nil) }
}

/// An empty view behind the pop-up, where `PopUpOpener` looks for it.
private struct PopUpAnchor: NSViewRepresentable {
    let opener: PopUpOpener

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        opener.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { opener.anchor = view }
}

extension View {
    /// This pop-up, for `opener` to open.
    func opened(by opener: PopUpOpener) -> some View {
        background { PopUpAnchor(opener: opener) }
    }
}
