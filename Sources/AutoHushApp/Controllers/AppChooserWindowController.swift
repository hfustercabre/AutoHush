import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The window that lists the apps Add an App can check; Other App… opens
/// the Finder's panel, in the Applications folder, for any other app.
@MainActor
final class AppChooserWindowController: HostedWindowController {
    private let model: AddAppModel

    init(model: AddAppModel) {
        self.model = model
        let hosting = Self.sizedToFit(AppChooserView(model: model, otherApp: {}, close: {}))
        super.init(content: hosting, title: AddAppText.chooserTitle)
        hosting.rootView = AppChooserView(model: model, otherApp: { [weak self] in self?.pickOtherApp() }, close: { [weak self] in self?.close() })
    }

    private func pickOtherApp() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = AddAppText.choose
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.model.chooseOther(at: url) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
