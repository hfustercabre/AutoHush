import AppKit
import SwiftUI

/// The "Add an App" window (W2). Closing it (Cancel, or its close button)
/// stops a check under way; nothing is kept.
@MainActor
final class AddAppWindowController: HostedWindowController, NSWindowDelegate {
    private let model: AddAppModel

    init(model: AddAppModel) {
        self.model = model
        let hosting = Self.sizedToFit(AddAppView(model: model, close: {}))
        super.init(content: hosting,
                   title: String(localized: "Add an App", comment: "Title of the window that checks how AutoHush can pause and play an app, then adds it, in its title bar"))
        window?.delegate = self
        hosting.rootView = AddAppView(model: model) { [weak self] in self?.close() }
    }

    func windowWillClose(_ notification: Notification) {
        model.windowClosed()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
