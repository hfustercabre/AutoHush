import AppKit
import ApplicationServices
import OSLog
import AutoHushKit

/// Makes a Safari web app from an address, the way a person does: it opens
/// the website in Safari and, once the user says to add it, uses Safari's
/// own File → Add to Dock, then clicks Add (keeping the name Safari
/// suggests) and closes the tab it opened. Nothing else is created or
/// changed; macOS has no other way to make one.
///
/// Safari makes the web app from the page it shows, so the site itself must
/// show first: a site can ask something first on another of its hosts
/// (YouTube's cookie page on consent.youtube.com, in the EU), and a web app
/// made from that page would open that page, named after it. Until the site
/// shows, it waits for the user to answer there; then the user adds it.
///
/// A website that already has a web app isn't added again: that one is
/// used. Cancelling stops it before Add is clicked (Safari's dialog is
/// cancelled too); after that, the web app exists and is left as it is.
package final class SafariWebAppMaker: WebAppMaking {
    /// How long the new web app may take to appear after Add.
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
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let clock: @Sendable () -> Date
    private let logger = Logger(category: "WebAppPlayer")

    /// `webApps` lists the web apps installed now (looked at afresh);
    /// `sameSite` tells whether one opens the site at an address (another
    /// country's site of the same service counts).
    package init(
        safari: any SafariDriving = SafariUI(),
        webApps: @escaping @Sendable () -> [SafariWebApp] = { SafariWebAppFinder().webApps() },
        sameSite: @escaping @Sendable (SafariWebApp, URL) -> Bool = { $0.opens($1) },
        isSealed: @escaping @Sendable (URL) -> Bool = { SafariWebApp.isSealed(at: $0) },
        checkAnswers: @escaping @Sendable (URL) async throws -> Void = { try await WebAddress.checkAnswers($0) },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.safari = safari
        self.webApps = webApps
        self.sameSite = sameSite
        self.isSealed = isSealed
        self.checkAnswers = checkAnswers
        self.sleep = sleep
        self.clock = clock
    }

    /// Throws `CancellationError` once cancelled before Add.
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
            try Task.checkCancellation()
            throw WebAppMakingError.browserFailed("the page didn't load in Safari")
        }
        try Task.checkCancellation()
        onStep(.opened)

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
            asking = nil
            onStep(.readyToAdd(site: site))
            guard await confirmAdd() else { throw CancellationError() }
            try Task.checkCancellation()
            // The user may have gone elsewhere since.
            if let shown = await safari.frontPageURL(), !WebAddress.isSameSite(shown, as: url) { continue }
            break
        }
        onStep(.adding)

        guard let suggested = await safari.addToDock(url) else {
            try Task.checkCancellation() // the dialog was cancelled instead of added
            throw WebAppMakingError.browserFailed("Safari's Add to Dock wasn't available")
        }
        logger.notice("Added a web app in Safari (suggested name: \(suggested, privacy: .private))")
        let deadline = clock().addingTimeInterval(Self.appearTimeout)
        while clock() < deadline {
            // Safari seals the new app last: it can't be opened before.
            if let app = webApps().first(where: { !before.contains($0.bundleID) }), isSealed(app.url) {
                // Launch Services learns of it only later: opening it by
                // its bundle ID needs it.
                LSRegisterURL(app.url as CFURL, true)
                await safari.closeTab(tab)
                let made = MadeWebApp(bundleID: app.bundleID, name: app.name, url: app.url, alreadyThere: false)
                onStep(.made(made))
                return made
            }
            await sleep(Self.pollInterval)
        }
        throw WebAppMakingError.browserFailed("no complete web app appeared after Add")
    }
}

/// The tab `SafariDriving` opened a website in, to close it afterwards.
package struct SafariTab: @unchecked Sendable {
    /// Its page's Accessibility element (a number in tests).
    let page: AnyHashable

    package init(page: AnyHashable) {
        self.page = page
    }
}

/// What `SafariWebAppMaker` does in Safari. A protocol, so tests stand in.
package protocol SafariDriving: Sendable {
    func isTrusted(prompt: Bool) async -> Bool
    /// Opens the address in Safari, in front; `false` when it couldn't.
    func open(_ url: URL) async -> Bool
    /// Waits until the page in Safari's front window has loaded and can be
    /// added: that tab; `nil` after a while.
    func waitForPage() async -> SafariTab?
    /// The address of the page in Safari's front window; `nil` when it
    /// can't be read.
    func frontPageURL() async -> URL?
    /// Chooses File → Add to Dock, makes sure the dialog has `url` (the page
    /// may have moved), and clicks Add, unless the task is cancelled
    /// meanwhile: then it clicks the dialog's Cancel. Returns the name
    /// Safari suggested; `nil` when the dialog didn't come or was cancelled.
    func addToDock(_ url: URL) async -> String?
    /// Closes `tab`, if it's still the one in front showing the same page:
    /// never a tab the user moved to since.
    func closeTab(_ tab: SafariTab) async
}

/// Safari, driven through Accessibility. Its menu items and the dialog's
/// fields and buttons are found by their identifiers, the same in every
/// language (measured on macOS 27): `AddToDock`, `CloseTab`,
/// `AddToDockFormNameTextField`, `AddToDockFormURLTextField`,
/// `AddToDockFormAddButton`, `AddToDockFormCancelButton`.
package struct SafariUI: SafariDriving {
    static let bundleID = "com.apple.Safari"
    /// The page gets at least this long, so the menu reflects the new tab.
    static let settleTime: TimeInterval = 1.5
    static let pageTimeout: TimeInterval = 30
    /// A heavy page can keep Safari from showing the dialog for several
    /// seconds (a first try on Deezer gave up after 5).
    static let dialogTimeout: TimeInterval = 15
    /// How long the dialog is left open before Add: it shows a letter for an
    /// icon at first and fetches the site's own, which took 0.5 to 1 s
    /// (YouTube Music, Spotify, Deezer). Nothing tells when it's there, and
    /// Add keeps what's shown.
    static let iconTime: TimeInterval = 3
    static let timeout: Float = 1
    /// How far up from the focused field the dialog is looked for.
    static let parentDepth = 30
    private let logger = Logger(category: "WebAppPlayer")

    package init() {}

    package func isTrusted(prompt: Bool) async -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }

    package func open(_ url: URL) async -> Bool {
        guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: configuration)
            return true
        } catch {
            return false
        }
    }

    package func waitForPage() async -> SafariTab? {
        try? await Task.sleep(for: .seconds(Self.settleTime))
        let deadline = Date().addingTimeInterval(Self.pageTimeout)
        while Date() < deadline, !Task.isCancelled {
            if let app = Self.safariElement(), Self.pageLoaded(in: app),
               let item = Self.menuItem("AddToDock", in: app), item.value(kAXEnabledAttribute) as? Bool == true,
               let page = Self.frontPage(in: app) {
                return SafariTab(page: page)
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return nil
    }

    package func frontPageURL() async -> URL? {
        guard let app = Self.safariElement(), let page = Self.frontPage(in: app) else { return nil }
        return page.value(kAXURLAttribute) as? URL
    }

    package func addToDock(_ url: URL) async -> String? {
        guard let app = Self.safariElement() else {
            logger.error("Add to Dock: Safari isn't running")
            return nil
        }
        // The user's click on Add to Dock put AutoHush in front: Safari shows
        // its dialog only while it's the active app, and its menu is looked
        // up afresh once it is.
        if let safari = NSRunningApplication.running(Self.bundleID), !safari.isActive {
            safari.activate()
            let deadline = Date().addingTimeInterval(2)
            while !safari.isActive, Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard let item = Self.menuItem("AddToDock", in: app) else {
            logger.error("Add to Dock: Safari's menu item wasn't found")
            return nil
        }
        let pressed = AXUIElementPerformAction(item, kAXPressAction as CFString)
        guard pressed == .success else {
            logger.error("Add to Dock: pressing Safari's menu item failed (\(pressed.rawValue, privacy: .public))")
            return nil
        }
        let deadline = Date().addingTimeInterval(Self.dialogTimeout)
        while Date() < deadline {
            if let add = Self.find("AddToDockFormAddButton", in: app) {
                let name = Self.find("AddToDockFormNameTextField", in: app)?.string(kAXValueAttribute) ?? ""
                if let field = Self.find("AddToDockFormURLTextField", in: app) {
                    let shown = field.string(kAXValueAttribute).flatMap(URL.init(string:))
                    if shown.flatMap({ $0.host() }).map(WebAddress.siteHost) != url.host().map(WebAddress.siteHost) {
                        AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, url.absoluteString as CFString)
                    }
                }
                try? await Task.sleep(for: .seconds(Self.iconTime))
                guard !Task.isCancelled else {
                    if let cancel = Self.find("AddToDockFormCancelButton", in: app) {
                        AXUIElementPerformAction(cancel, kAXPressAction as CFString)
                    }
                    logger.notice("Add to Dock cancelled")
                    return nil
                }
                guard AXUIElementPerformAction(add, kAXPressAction as CFString) == .success else { return nil }
                return name
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        logger.error("Add to Dock: Safari's dialog didn't come within \(Int(Self.dialogTimeout), privacy: .public) s")
        return nil
    }

    package func closeTab(_ tab: SafariTab) async {
        guard let app = Self.safariElement(), let front = Self.frontPage(in: app), AnyHashable(front) == tab.page,
              let item = Self.menuItem("CloseTab", in: app)
        else {
            logger.notice("The tab Add a Web App opened isn't in front any more: left open")
            return
        }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
    }

    // MARK: - Accessibility

    private static func safariElement() -> AXUIElement? {
        guard let safari = NSRunningApplication.running(bundleID) else { return nil }
        let app = AXUIElementCreateApplication(safari.processIdentifier)
        AXUIElementSetMessagingTimeout(app, timeout)
        return app
    }

    /// The front window's page has loaded (Safari's browser view says so in
    /// its identifier, e.g. "BrowserView?IsPageLoaded=true&…").
    private static func pageLoaded(in app: AXUIElement) -> Bool {
        guard let window = app.element(kAXFocusedWindowAttribute) else { return false }
        return first(in: window, depth: 6) { $0.string("AXIdentifier")?.contains("IsPageLoaded=true") == true } != nil
    }

    /// The page in the front window's tab: the same element for as long as
    /// that tab shows that page.
    private static func frontPage(in app: AXUIElement) -> AXUIElement? {
        guard let window = app.element(kAXFocusedWindowAttribute) else { return nil }
        return first(in: window, depth: 8) { $0.string(kAXRoleAttribute) == "AXWebArea" }
    }

    private static func menuItem(_ identifier: String, in app: AXUIElement) -> AXUIElement? {
        guard let bar = app.element(kAXMenuBarAttribute) else { return nil }
        for menu in bar.children.flatMap(\.children) {
            if let item = menu.children.first(where: { $0.string("AXIdentifier") == identifier }) {
                return item
            }
        }
        return nil
    }

    /// An element of the dialog, by identifier: in the front window's sheet,
    /// else around the focused field.
    private static func find(_ identifier: String, in app: AXUIElement) -> AXUIElement? {
        let matches: (AXUIElement) -> Bool = { $0.string("AXIdentifier") == identifier }
        var roots: [AXUIElement] = []
        if let window = app.element(kAXFocusedWindowAttribute) { roots.append(window) }
        if let focused = app.element(kAXFocusedUIElementAttribute) {
            var node = focused
            for _ in 0..<parentDepth {
                guard let parent = node.element(kAXParentAttribute) else { break }
                if parent.string(kAXRoleAttribute) == "AXSheet" { roots.append(parent) }
                node = parent
            }
        }
        for root in roots {
            for sheet in [root] + root.children where sheet.string(kAXRoleAttribute) == "AXSheet" {
                if let found = first(in: sheet, depth: 4, where: matches) { return found }
            }
        }
        return nil
    }

    private static func first(in element: AXUIElement, depth: Int, where matches: (AXUIElement) -> Bool) -> AXUIElement? {
        if matches(element) { return element }
        guard depth > 0 else { return nil }
        for child in element.children {
            if let found = first(in: child, depth: depth - 1, where: matches) { return found }
        }
        return nil
    }
}
