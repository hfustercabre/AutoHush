import AppKit
import ApplicationServices
import AutoHushKit

/// Makes a Safari web app from an address, the way a person does: it opens
/// the website in Safari and, once the user says to add it, opens Safari's
/// own File → Add to Dock, where the user can rename the web app and clicks
/// Add (or Cancel: then it waits for Add to Dock again), and closes the tab
/// it opened. Nothing else is created or changed; macOS has no other way to
/// make one.
///
/// Safari makes the web app from the page it shows, so the site itself must
/// show first: a site can ask something first on another of its hosts
/// (YouTube's cookie page on consent.youtube.com, in the EU), and a web app
/// made from that page would open that page, named after it. Until the site
/// shows, it waits for the user to answer there; then the user adds it.
///
/// A website that already has a web app isn't added again: that one is
/// used, and nothing is opened in Safari. Cancelling stops it (Safari's
/// dialog is cancelled too) and takes away what it left: the tab it
/// opened, and a web app Safari made all the same (Add was clicked just
/// before), quit and moved to the Trash (the user, 2026-10-22).
package final class SafariWebAppMaker: WebAppMaking {
    /// Once Safari's dialog closes, how long the new web app may take to
    /// appear (as long as after AutoHush's own Add before); none by then,
    /// the dialog was closed with Cancel. One that comes later still is
    /// taken at the next Add to Dock.
    static let appearTimeout: TimeInterval = 20
    static let pollInterval: TimeInterval = 0.25
    /// While another site asks something first, how often Safari's page is
    /// looked at again.
    static let siteCheckInterval: TimeInterval = 1

    private let safari: any SafariDriving
    private let webApps: @Sendable () -> [SafariWebApp]
    private let sameSite: @Sendable (SafariWebApp, URL) -> Bool
    private let isSealed: @Sendable (URL) -> Bool
    private let checkAnswers: @Sendable (URL) async throws -> Void
    /// Quits a web app this add made after it was cancelled, and moves it to the Trash.
    private let discard: @Sendable (SafariWebApp) -> Void
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let clock: @Sendable () -> Date
    private let logger = AutoHushLogger(category: "WebAppPlayer")

    /// `webApps` lists the web apps installed now (looked at afresh);
    /// `sameSite` tells whether one opens the site at an address (another
    /// country's site of the same service counts).
    package init(
        safari: any SafariDriving = SafariUI(),
        webApps: @escaping @Sendable () -> [SafariWebApp] = { SafariWebAppFinder().webApps() },
        sameSite: @escaping @Sendable (SafariWebApp, URL) -> Bool = { $0.opens($1) },
        isSealed: @escaping @Sendable (URL) -> Bool = { SafariWebApp.isSealed(at: $0) },
        checkAnswers: @escaping @Sendable (URL) async throws -> Void = { try await WebAddress.checkAnswers($0) },
        discard: @escaping @Sendable (SafariWebApp) -> Void = { SafariWebAppMaker.quitAndTrash($0) },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.safari = safari
        self.webApps = webApps
        self.sameSite = sameSite
        self.isSealed = isSealed
        self.checkAnswers = checkAnswers
        self.discard = discard
        self.sleep = sleep
        self.clock = clock
    }

    /// Throws `CancellationError` once cancelled before Add. Off the
    /// caller's actor: between its steps it lists the web apps on the disk,
    /// checks their signatures and registers the new one, which all block.
    @concurrent
    package func makeWebApp(from address: String,
                            onStep: @escaping @Sendable (WebAppMakingStep) -> Void,
                            confirmAdd: @escaping @Sendable () async -> Bool) async throws -> MadeWebApp {
        guard let url = WebAddress.url(from: address) else { throw WebAppMakingError.notAWebAddress }
        try await checkAnswers(url)
        try Task.checkCancellation()
        onStep(.checked)

        if let existing = webApps().first(where: { sameSite($0, url) }) {
            let made = MadeWebApp(bundleID: existing.bundleID, name: existing.name, url: existing.url, alreadyThere: true)
            onStep(.made(made))
            return made
        }
        guard await safari.isTrusted(prompt: true) else { throw WebAppMakingError.accessibilityDenied }

        let before = Set(webApps().map(\.bundleID))
        try Task.checkCancellation()
        guard await safari.open(url) else { throw WebAppMakingError.browserFailed("Safari couldn't open \(url.absoluteString)") }
        guard let tab = await safari.waitForPage() else {
            if Task.isCancelled {
                // Cancelled while the page loaded: the tab opened for it goes too.
                await takeAway(url, since: before, tab: nil, waitsForApp: false)
                throw CancellationError()
            }
            throw WebAppMakingError.browserFailed("the page didn't load in Safari")
        }
        // The tab to close once added, or cancelled: the one opened, or, once
        // the site asked something first, the page it then showed in it
        // (answering loads another page). Never a tab the user moves to later.
        var addedTab = tab
        // Add clicked in Safari's dialog: a web app may come even once cancelled.
        var addClicked = false
        do {
            try Task.checkCancellation()
            onStep(.opened)
            return try await add(url, since: before, tab: &addedTab, addClicked: &addClicked, onStep: onStep, confirmAdd: confirmAdd)
        } catch is CancellationError {
            await takeAway(url, since: before, tab: addedTab, waitsForApp: addClicked)
            throw CancellationError()
        }
    }

    /// From the page loaded in Safari: Add to Dock, once the site itself
    /// shows and the user clicked, until a new web app comes.
    private func add(_ url: URL, since before: Set<String>, tab addedTab: inout SafariTab, addClicked: inout Bool,
                     onStep: @escaping @Sendable (WebAppMakingStep) -> Void,
                     confirmAdd: @escaping @Sendable () async -> Bool) async throws -> MadeWebApp {
        let site = url.host() ?? url.absoluteString
        var asking: String?
        while true {
            if let shown = await safari.frontPageURL(), !WebAddress.isSameSite(shown, as: url) {
                let host = shown.host() ?? shown.absoluteString
                if asking != host {
                    asking = host
                    logger.notice("Safari shows another site first: waiting for the user to answer it")
                    onStep(.siteAsks(shown: host, site: site))
                }
                await sleep(Self.siteCheckInterval)
                try Task.checkCancellation()
                continue
            }
            if asking != nil, let shown = await safari.frontTab() { addedTab = shown }
            asking = nil
            onStep(.readyToAdd(site: site))
            guard await confirmAdd() else { throw CancellationError() }
            try Task.checkCancellation()
            // Added after all, later than AutoHush waited for it.
            if let made = await newWebApp(since: before, tab: addedTab, onStep: onStep) { return made }
            // The user may have gone elsewhere since.
            if let shown = await safari.frontPageURL(), !WebAddress.isSameSite(shown, as: url) { continue }
            onStep(.adding)
            switch await safari.addToDock(url) {
            case .unavailable:
                try Task.checkCancellation()
                throw WebAppMakingError.browserFailed("Safari's Add to Dock wasn't available")
            case .cancelled:
                throw CancellationError()
            case .closed:
                addClicked = true
            }
            // Added, the new web app comes; closed with Cancel, none does.
            let deadline = clock().addingTimeInterval(Self.appearTimeout)
            while clock() < deadline {
                if let made = await newWebApp(since: before, tab: addedTab, onStep: onStep) { return made }
                await sleep(Self.pollInterval)
                try Task.checkCancellation()
            }
            logger.notice("Safari’s Add to Dock closed without a new web app: waiting for Add to Dock again")
            onStep(.notAdded)
        }
    }

    /// What a cancelled add of `url` leaves goes: its tab (`nil`: not known
    /// yet, the page still loading: the tab in front, if it shows the site),
    /// then, when Add was clicked in Safari's dialog, the web app Safari
    /// makes all the same for that site (as long as `appearTimeout`), quit
    /// and moved to the Trash: never one of another site, made meanwhile.
    /// Off the cancelled task, so its waits aren't cut short.
    private func takeAway(_ url: URL, since before: Set<String>, tab: SafariTab?, waitsForApp: Bool) async {
        let (safari, webApps, sameSite, isSealed, discard, sleep, clock, logger)
            = (safari, webApps, sameSite, isSealed, discard, sleep, clock, logger)
        await Task.detached {
            if let tab {
                await safari.closeTab(tab)
            } else if let shown = await safari.frontPageURL(), WebAddress.isSameSite(shown, as: url),
                      let front = await safari.frontTab() {
                await safari.closeTab(front)
            }
            guard waitsForApp else { return }
            let deadline = clock().addingTimeInterval(Self.appearTimeout)
            while clock() < deadline {
                // Once Safari is done with it (sealed), so nothing of it is left behind.
                if let app = webApps().first(where: { !before.contains($0.bundleID) && sameSite($0, url) }), isSealed(app.url) {
                    logger.notice("A web app made by a cancelled add: quit and moved to the Trash")
                    discard(app)
                    return
                }
                await sleep(Self.pollInterval)
            }
        }.value
    }

    /// Quits `app` if it runs, and moves it to the Trash (never deleted).
    package static func quitAndTrash(_ app: SafariWebApp) {
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) { running.terminate() }
        do {
            try FileManager.default.trashItem(at: app.url, resultingItemURL: nil)
        } catch {
            AutoHushLogger(category: "WebAppPlayer").error("A cancelled add’s web app couldn’t be moved to the Trash: \(error)")
        }
    }

    /// The web app Safari made since `before`, once it's complete: Safari
    /// seals it last, and it can't be opened before. Then it's registered
    /// (Launch Services learns of it only later, and opening it by its
    /// bundle ID needs it) and AutoHush's Safari tab closed.
    private func newWebApp(since before: Set<String>, tab: SafariTab,
                           onStep: @Sendable (WebAppMakingStep) -> Void) async -> MadeWebApp? {
        guard let app = webApps().first(where: { !before.contains($0.bundleID) }), isSealed(app.url) else { return nil }
        LSRegisterURL(app.url as CFURL, true)
        await safari.closeTab(tab)
        logger.notice("Added a web app in Safari")
        let made = MadeWebApp(bundleID: app.bundleID, name: app.name, url: app.url, alreadyThere: false)
        onStep(.made(made))
        return made
    }
}
