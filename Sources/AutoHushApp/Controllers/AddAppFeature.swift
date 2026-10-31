import AppKit
import AutoHushKit
import CheckPanel

/// Add an App… as a feature of its own: its model (made when first opened),
/// its windows (the window, the list of apps, the warning before a check),
/// the check's panel, and the Mac's output muted while a check runs that
/// can't mute only its app. AppDelegate opens it and puts the output back
/// as AutoHush quits and at launch; what it needs from the rest of AutoHush
/// it asks of its host (X17, the full check, 2026-10-19).
@MainActor
final class AddAppFeature {
    /// What it works through on the Mac.
    struct System {
        /// The Mac's output, muted while a check runs that can't mute only its app.
        var outputMute = OutputMute()
        /// Tests' stand-ins for the apps on the Mac and the check's helper;
        /// `nil`: `AppReader` and AutoHush's own helper, found as the model
        /// is first made.
        var standIns: (reader: any AppReading, helper: any CheckHelping)?
        /// Whether Mission Control's desktop shortcuts are on, read as the
        /// warning before a check opens and each time it comes back in front
        /// (`DesktopShortcuts`); tests say.
        var desktopShortcutsOn: () -> Bool = { DesktopShortcuts.areOn }
    }

    private weak var host: any AddAppHost?
    private let system: System
    private let keptChecks: KeptCheckStore
    /// Checks an app and adds it; made when first opened.
    private(set) var model: AddAppModel?
    private(set) var window: AddAppWindowController?
    /// The list of apps its first step opens.
    private(set) var chooserWindow: AppChooserWindowController?
    /// Shown before a check starts.
    private(set) var warningWindow: CheckWarningWindowController?
    /// The check's progress, at the bottom right of the screen while it runs.
    private let panel = CheckPanelController()
    private let logger = AutoHushLogger(category: "AddApp")

    init(host: any AddAppHost, system: System = System(), keptChecks: KeptCheckStore) {
        self.host = host
        self.system = system
        self.keptChecks = keptChecks
    }

    /// The "Add an App" window, from its first step unless it's open.
    func open() {
        let model = model ?? makeModel()
        self.model = model
        if window == nil { window = AddAppWindowController(model: model) }
        if window?.isOpen != true { model.reset() }
        window?.show()
    }

    /// AutoHush quits: the Mac's output, muted for a check, is put back.
    func quit() {
        system.outputMute.restore()
    }

    /// At launch: the Mac's output muted for a check AutoHush quit or
    /// crashed during is put back.
    func putBackWhatWasLeft() {
        system.outputMute.restoreIfLeft()
    }

    private func makeModel() -> AddAppModel {
        if let standIns = system.standIns {
            return AddAppModel(reader: standIns.reader, helper: standIns.helper, host: host, presenter: self, keptChecks: keptChecks)
        }
        let helper = PlayerCheckHelper.bundled
        if helper == nil { logger.error("Add an App: the check’s helper is missing from the app") }
        return AddAppModel(reader: AppReader(helper: helper, host: host), helper: helper, host: host, presenter: self,
                           keptChecks: keptChecks)
    }
}

extension AddAppFeature: AddAppPresenting {
    func showChooser() {
        guard let model else { return }
        if chooserWindow == nil { chooserWindow = AppChooserWindowController(model: model) }
        chooserWindow?.show()
    }

    func closeChooser() {
        chooserWindow?.close()
    }

    /// The warning before the check (W6), for the chosen app; a new one
    /// replaces the last.
    func showWarning() {
        guard let model, let app = model.chosen else { return }
        warningWindow?.close()
        let shortcutsOn = system.desktopShortcutsOn
        let window = CheckWarningWindowController(app: app, muting: model.checkMuting,
                                                  desktopShortcutsOff: { !shortcutsOn() }) { [weak model] in model?.startCheck() }
        warningWindow = window
        window.show()
    }

    func closeWarning() {
        warningWindow?.close()
    }

    func checkStarted(_ app: CheckableApp) {
        // AutoHush's player isn't resumed while the check plays and pauses its app.
        host?.holdsPlayerForCheck(true)
        guard let model else { return }
        // A check that can't mute only its app (no taps): the Mac's output, meanwhile.
        if model.checkMuting != .app { system.outputMute.mute() }
        panel.show(app, model: model)
    }

    func checkEnded() {
        system.outputMute.restore()
        panel.hide()
        host?.holdsPlayerForCheck(false)
        window?.bringForward() // its result, or why there's none, in view
    }

    var canMuteOutput: Bool { system.outputMute.canMute }

    var hasCheckLog: Bool { PlayerCheckHelper.newestLog != nil }

    func showCheckLog() {
        guard let log = PlayerCheckHelper.newestLog else { return }
        NSWorkspace.shared.open(log)
    }

    func openMenuBarSettings() {
        SystemSettingsPane.menuBar.open()
    }

    func closeWindow() {
        window?.close()
    }
}
