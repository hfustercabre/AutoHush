import AppKit
import SwiftUI

/// What `AppDelegate` needs of the window; tests stand in for it.
@MainActor
protocol AddWebAppPresenting: AnyObject {
    var isOpen: Bool { get }
    func show()
    func close()
}

@MainActor
final class AddWebAppWindowController: HostedWindowController, AddWebAppPresenting, NSWindowDelegate {
    private let model: AddWebAppModel

    init(model: AddWebAppModel, settings: SettingsModel) {
        self.model = model
        let hosting = Self.sizedToFit(AddWebAppView(model: model, settings: settings, close: {}))
        super.init(content: hosting,
                   title: String(localized: "Add a Web App", comment: "Title of the window that makes a website a Safari web app, in its title bar"))
        window?.delegate = self
        floatsInCorner = true // Safari, then the web app, come in front meanwhile
        hosting.rootView = AddWebAppView(model: model, settings: settings) { [weak self] in self?.close() }
    }

    /// Closing it (Cancel, Later or its close button) stops an add under way.
    func windowWillClose(_ notification: Notification) {
        model.windowClosed()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
