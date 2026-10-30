import AppKit
import SwiftUI
import AutoHushKit

/// The window shown before a check starts (W6): its Start runs the check.
@MainActor
final class CheckWarningWindowController: HostedWindowController {
    init(app: CheckableApp, muting: AddAppModel.CheckMuting, desktopShortcutsOff: Bool = !DesktopShortcuts.areOn,
         openKeyboardSettings: @escaping () -> Void = { SystemSettingsPane.keyboard.open() },
         start: @escaping @MainActor () -> Void) {
        let hosting = Self.sizedToFit(CheckWarningView(app: app, muting: muting, desktopShortcutsOff: desktopShortcutsOff,
                                                       openKeyboardSettings: openKeyboardSettings, start: {}, cancel: {}))
        super.init(content: hosting, title: AddAppText.warningTitle(app.name))
        hosting.rootView = CheckWarningView(app: app, muting: muting, desktopShortcutsOff: desktopShortcutsOff,
                                            openKeyboardSettings: openKeyboardSettings, start: { [weak self] in
            self?.close()
            start()
        }, cancel: { [weak self] in self?.close() })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
