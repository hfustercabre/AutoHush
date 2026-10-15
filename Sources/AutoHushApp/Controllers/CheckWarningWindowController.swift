import AppKit
import SwiftUI

/// The window shown before a check starts (W6): its Start runs the check.
@MainActor
final class CheckWarningWindowController: HostedWindowController {
    init(app: CheckableApp, muted: Bool, start: @escaping @MainActor () -> Void) {
        let hosting = Self.sizedToFit(CheckWarningView(app: app, muted: muted, start: {}, cancel: {}))
        super.init(content: hosting, title: AddAppText.warningTitle(app.name))
        hosting.rootView = CheckWarningView(app: app, muted: muted, start: { [weak self] in
            self?.close()
            start()
        }, cancel: { [weak self] in self?.close() })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
