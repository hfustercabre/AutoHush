import AppKit
import ApplicationServices
import OSLog
import AutoHushKit

/// Makes a Safari web app from an address, the way a person does: it opens
/// the website in Safari and, once the user says to add it, opens Safari's
/// own File → Add to Dock, where the user can rename the web app and clicks
/// Add (or Cancel: then it waits for Add to Dock again), and closes the tab
/// it opened. Nothing else is created or
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
    /// Once Safari's dialog closes, how long the new web app may take to
    /// appear; none by then, the dialog was closed with Cancel. One that
    /// comes later still is taken at the next Add to Dock.
    static let appearTimeout: TimeInterval = 10
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
        // The tab to close once added: the one opened, or, once the site
        // asked something first, the page it then showed in it (answering
        // loads another page). Never a tab the user moves to later.
        var addedTab = tab
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
                break
            }
            // Added, the new web app comes; closed with Cancel, none does.
            let deadline = clock().addingTimeInterval(Self.appearTimeout)
            while clock() < deadline {
                if let made = await newWebApp(since: before, tab: addedTab, onStep: onStep) { return made }
                await sleep(Self.pollInterval)
                try Task.checkCancellation()
            }
            logger.notice("Safari's Add to Dock closed without a new web app: waiting for Add to Dock again")
            onStep(.notAdded)
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

/// How Safari's Add to Dock dialog ended.
package enum AddToDockResult: Equatable, Sendable {
    /// It didn't open: Safari's menu item or its dialog wasn't there.
    case unavailable
    /// The user closed it, with Add or with Cancel: the new web app, or none,
    /// tells which.
    case closed
    /// The add was cancelled in AutoHush meanwhile: the dialog was cancelled.
    case cancelled
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
    /// The tab showing the page in Safari's front window now; `nil` when
    /// there's none.
    func frontTab() async -> SafariTab?
    /// Chooses File → Add to Dock, makes sure the dialog has `url` (the page
    /// may have moved), and waits while the user names the web app and
    /// clicks Add (or Cancel) there. If the task is cancelled meanwhile, it
    /// clicks the dialog's Cancel.
    func addToDock(_ url: URL) async -> AddToDockResult
    /// Closes `tab` (its window, when it's the window's only tab), if it's
    /// still the one in front showing the same page: never a tab the user
    /// moved to since.
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
    /// While the dialog is open, how often it's looked at: still there, or
    /// closed by the user.
    static let dialogCheckInterval: TimeInterval = 0.3
    static let timeout: Float = 1
    /// How far up from the focused field the dialog is looked for.
    static let parentDepth = 30
    /// Accessibility calls block: they run here, one at a time, as the
    /// players' do.
    private static let queue = DispatchQueue(label: "AutoHush.SafariUI", qos: .userInitiated)
    private let logger = Logger(category: "WebAppPlayer")

    package init() {}

    package func isTrusted(prompt: Bool) async -> Bool {
        await Self.queue.run { AccessibilityPermission.isTrusted(prompt: prompt) }
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
            let tab = await Self.queue.run { () -> SafariTab? in
                guard let app = Self.safariElement(), Self.pageLoaded(in: app),
                      let item = Self.menuItem("AddToDock", in: app), item.value(kAXEnabledAttribute) as? Bool == true,
                      let page = Self.frontPage(in: app)
                else { return nil }
                return SafariTab(page: page)
            }
            if let tab { return tab }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return nil
    }

    package func frontTab() async -> SafariTab? {
        await Self.queue.run {
            guard let app = Self.safariElement(), let page = Self.frontPage(in: app) else { return nil }
            return SafariTab(page: page)
        }
    }

    package func frontPageURL() async -> URL? {
        await Self.queue.run {
            guard let app = Self.safariElement(), let page = Self.frontPage(in: app) else { return nil }
            return page.value(kAXURLAttribute) as? URL
        }
    }

    package func addToDock(_ url: URL) async -> AddToDockResult {
        guard NSRunningApplication.running(Self.bundleID) != nil else {
            logger.error("Add to Dock: Safari isn't running")
            return .unavailable
        }
        // The user's click on Add to Dock put AutoHush in front: Safari shows
        // its dialog only while it's the active app, and its menu is looked
        // up afresh once it is.
        await Self.bringSafariToFront()
        let pressed = await Self.queue.run { () -> AXError? in
            guard let app = Self.safariElement(), let item = Self.menuItem("AddToDock", in: app) else { return nil }
            return AXUIElementPerformAction(item, kAXPressAction as CFString)
        }
        guard let pressed else {
            logger.error("Add to Dock: Safari's menu item wasn't found")
            return .unavailable
        }
        guard pressed == .success else {
            logger.error("Add to Dock: pressing Safari's menu item failed (\(pressed.rawValue, privacy: .public))")
            return .unavailable
        }
        // The dialog, once it shows, with its address set back to the one
        // typed if the page moved.
        let deadline = Date().addingTimeInterval(Self.dialogTimeout)
        var shows = false
        while !shows, Date() < deadline {
            shows = await Self.queue.run { () -> Bool in
                guard let app = Self.safariElement(), Self.find("AddToDockFormAddButton", in: app) != nil else { return false }
                if let field = Self.find("AddToDockFormURLTextField", in: app) {
                    let shown = field.string(kAXValueAttribute).flatMap(URL.init(string:))
                    if shown.flatMap({ $0.host() }).map(WebAddress.siteHost) != url.host().map(WebAddress.siteHost) {
                        AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, url.absoluteString as CFString)
                    }
                }
                return true
            }
            if !shows { try? await Task.sleep(for: .milliseconds(200)) }
        }
        guard shows else {
            logger.error("Add to Dock: Safari's dialog didn't come within \(Int(Self.dialogTimeout), privacy: .public) s")
            return .unavailable
        }
        // The user names the web app and clicks Add (or Cancel) there.
        while !Task.isCancelled {
            let open = await Self.queue.run { () -> Bool in
                guard let app = Self.safariElement() else { return false }
                return Self.find("AddToDockFormAddButton", in: app) != nil
            }
            guard open else { return .closed }
            try? await Task.sleep(for: .seconds(Self.dialogCheckInterval))
        }
        await Self.queue.run {
            guard let app = Self.safariElement(), let button = Self.find("AddToDockFormCancelButton", in: app) else { return }
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
        logger.notice("Add to Dock cancelled")
        return .cancelled
    }

    package func closeTab(_ tab: SafariTab) async {
        let closed = await Self.queue.run { () -> Bool? in
            guard let app = Self.safariElement(), let front = Self.frontPage(in: app), AnyHashable(front) == tab.page else {
                return nil
            }
            // Safari disables Close Tab for a window's only tab (measured on
            // macOS 27): its window is closed instead.
            let closeTab = Self.menuItem("CloseTab", in: app)
            let isOnlyTab = closeTab?.value(kAXEnabledAttribute) as? Bool == false
            guard let item = isOnlyTab ? Self.menuItem("CloseWindow", in: app) : closeTab else { return false }
            AXUIElementPerformAction(item, kAXPressAction as CFString)
            return true
        }
        switch closed {
        case nil: logger.notice("The tab Add a Web App opened isn't in front any more: left open")
        case false?: logger.error("Safari's Close Tab wasn't found: the tab Add a Web App opened was left open")
        case true?: break
        }
    }

    /// Makes Safari the active app, and waits a moment for it to be.
    @MainActor
    private static func bringSafariToFront() async {
        guard let safari = NSRunningApplication.running(bundleID), !safari.isActive else { return }
        safari.activate()
        let deadline = Date().addingTimeInterval(2)
        while !safari.isActive, Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(300))
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
