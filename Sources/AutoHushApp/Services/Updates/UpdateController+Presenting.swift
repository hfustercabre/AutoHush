import AppKit

// UpdateController: the update window.
extension UpdateController {
    /// The menu's "Install AutoHush 0.3.8…": shows the update found. Clicked
    /// from a notification that no longer applies, it checks again instead.
    func presentAvailableUpdate() {
        guard let release = availableUpdate else {
            checkFromUser()
            return
        }
        showAlert { self.present(.available(release)) }
    }

    func canInstall(_ release: AppRelease) -> Bool {
        installer.unavailability == nil && release.diskImage != nil
    }

    func reportOffer() {
        guard let release = availableUpdate else { return onOffer(nil) }
        let state: UpdateOffer.State = isInstalling ? .installing : downloads.isKept(release) ? .downloaded : .available
        onOffer(UpdateOffer(release: release, state: state))
    }

    func availableStatus(_ release: AppRelease) -> String {
        let version = release.version.description
        return downloads.isKept(release)
            ? String(localized: "Version \(version) is downloaded and ready to install.",
                     comment: "Update status in Settings; %@ is a version number")
            : String(localized: "Version \(version) is available.",
                     comment: "Update status in Settings; %@ is a version number")
    }

    func present(_ result: UpdateCheckResult) {
        guard let current = currentVersion else { return } // checks need it, so never missing here
        switch result {
        case .available(let release):
            presentAvailable(release, running: current)
        case .upToDate:
            InfoAlert.show(
                String(localized: "AutoHush Is Up to Date", comment: "Alert title"),
                String(localized: "You have the latest version, \(current.description).",
                       comment: "Alert text; %@ is the installed version"),
                run: runAlert
            )
        case .noReleases:
            InfoAlert.show(
                String(localized: "No Releases Yet", comment: "Alert title"),
                String(localized: "No AutoHush release has been published on GitHub yet.", comment: "Alert text"),
                run: runAlert
            )
        }
    }

    /// Offers to install `release`, with its notes, or, when AutoHush can't,
    /// says how to.
    private func presentAvailable(_ release: AppRelease, running: AppVersion) {
        let prompt = UpdatePrompt(
            release: release, running: running, isDownloaded: downloads.image(for: release) != nil,
            canInstall: canInstall(release), isHomebrewInstall: UpdateChecker.isHomebrewInstall
        )
        let alert = NSAlert()
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        for button in prompt.buttons {
            let added = alert.addButton(withTitle: button.title)
            // Return presses the first button, as AppKit sets it; Escape, Later.
            if button.choice == .later { added.keyEquivalent = "\u{1b}" }
        }
        if let notes = release.notes { alert.accessoryView = Self.notesView(notes) }
        let index = runAlert(alert).rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard prompt.buttons.indices.contains(index) else { return }
        switch prompt.buttons[index].choice {
        case .install: Task { await install(release, userInitiated: true) }
        case .openReleasePage: openURL(release.pageURL)
        case .later: break
        }
    }

    /// The release notes in a small scrolling box, as tall as they need up to
    /// a limit, showing their start.
    static func notesView(_ markdown: String) -> NSView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 100))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.isEditable = false
        // Not selectable either, so the alert doesn't make it the first
        // responder, which would scroll it to the middle.
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.textStorage?.setAttributedString(ReleaseNotes.text(from: markdown))
        textView.sizeToFit()

        scrollView.frame.size.height = min(max(textView.frame.height + 4, 48), 180)
        scrollView.documentView = textView
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return scrollView
    }

    /// Says why `release` couldn't be installed (`reason`), and offers its
    /// page to install it by hand.
    func presentInstallError(_ reason: String, release: AppRelease) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Couldn’t Install the Update", comment: "Alert title")
        alert.informativeText = reason
        alert.addButton(withTitle: String(localized: "Open Release Page", comment: "Update alert button"))
        alert.addButton(withTitle: String(localized: "Later", comment: "Button that closes it for now: an update alert, or a window that learns a web app's controls (the learning window, the Add a Web App window)"))
            .keyEquivalent = "\u{1b}" // Escape; Return opens the page
        if runAlert(alert) == .alertFirstButtonReturn {
            openURL(release.pageURL)
        }
    }
}
