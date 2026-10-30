import AppKit
import SwiftUI

/// The "Add a Web App" window: an address, then Safari's steps and the
/// learning, floating in the corner while Safari and the web app come in
/// front.
@MainActor
final class AddWebAppWindowController: HostedWindowController, AddWebAppPresenting, NSWindowDelegate {
    private let model: AddWebAppModel

    init(model: AddWebAppModel, settings: SettingsModel) {
        self.model = model
        let hosting = Self.sizedToFit(AddWebAppView(model: model, settings: settings, close: {}))
        // Floating: Safari, then the web app, come in front meanwhile.
        super.init(content: hosting,
                   title: String(localized: "Add a Web App", comment: "Title of the window that makes a website a Safari web app, in its title bar"),
                   floatsInCorner: true)
        window?.delegate = self
        hosting.rootView = AddWebAppView(model: model, settings: settings) { [weak self] in self?.close() }
    }

    /// Closing it (Cancel, Later or its close button) stops an add under way.
    func windowWillClose(_ notification: Notification) {
        model.windowClosed()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
