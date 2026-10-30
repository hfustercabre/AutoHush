import AppKit
import ApplicationServices
import AutoHushKit

/// Safari, driven through Accessibility. Its menu items and the dialog's
/// fields and buttons are found by their identifiers, the same in every
/// language (measured on macOS 27): `AddToDock` (Safari 17.4 on macOS 14.4:
/// `generateWebAppForCurrentPage:`), `CloseTab`,
/// `AddToDockFormNameTextField`, `AddToDockFormURLTextField`,
/// `AddToDockFormAddButton`, `AddToDockFormCancelButton`.
package struct SafariUI: SafariDriving {
    package static let bundleID = "com.apple.Safari"
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
    private let logger = AutoHushLogger(category: "WebAppPlayer")

    init() {}

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
                      let item = Self.addToDockItem(in: app), item.value(kAXEnabledAttribute) as? Bool == true,
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
            logger.error("Add to Dock: Safari isn’t running")
            return .unavailable
        }
        // The user's click on Add to Dock put AutoHush in front: Safari shows
        // its dialog only while it's the active app, and its menu is looked
        // up afresh once it is.
        await Self.bringSafariToFront()
        let pressed = await Self.queue.run { () -> AXError? in
            guard let app = Self.safariElement(), let item = Self.addToDockItem(in: app) else { return nil }
            return AXUIElementPerformAction(item, kAXPressAction as CFString)
        }
        guard let pressed else {
            logger.error("Add to Dock: Safari’s menu item wasn’t found")
            return .unavailable
        }
        guard pressed == .success else {
            logger.error("Add to Dock: pressing Safari’s menu item failed (\(pressed.rawValue, privacy: .public))")
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
            logger.error("Add to Dock: Safari’s dialog didn’t come within \(Int(Self.dialogTimeout), privacy: .public) s")
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
            return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        }
        switch closed {
        case nil: logger.notice("The tab Add a Web App opened isn’t in front any more: left open")
        case false?: logger.error("Safari’s Close Tab wasn’t found or didn’t take: the tab Add a Web App opened was left open")
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

    // Every element read here waits `timeout` (macOS's 6 s otherwise): each
    // one is given it as it's found.

    private static func safariElement() -> AXUIElement? {
        guard let safari = NSRunningApplication.running(bundleID) else { return nil }
        return AXUIElement.application(safari.processIdentifier, timeout: timeout)
    }

    /// The front window's page has loaded (Safari's browser view says so in
    /// its identifier, e.g. "BrowserView?IsPageLoaded=true&…").
    private static func pageLoaded(in app: AXUIElement) -> Bool {
        guard let window = app.element(kAXFocusedWindowAttribute, timeout: timeout) else { return false }
        return first(in: window, depth: 6) { $0.string("AXIdentifier")?.contains("IsPageLoaded=true") == true } != nil
    }

    /// The page in the front window's tab: the same element for as long as
    /// that tab shows that page.
    private static func frontPage(in app: AXUIElement) -> AXUIElement? {
        guard let window = app.element(kAXFocusedWindowAttribute, timeout: timeout) else { return nil }
        return first(in: window, depth: 8) { $0.string(kAXRoleAttribute) == "AXWebArea" }
    }

    /// File → Add to Dock…, by either name Safari gives it.
    private static func addToDockItem(in app: AXUIElement) -> AXUIElement? {
        menuItem("AddToDock", in: app) ?? menuItem("generateWebAppForCurrentPage:", in: app)
    }

    private static func menuItem(_ identifier: String, in app: AXUIElement) -> AXUIElement? {
        guard let bar = app.element(kAXMenuBarAttribute, timeout: timeout) else { return nil }
        for menu in bar.children(timeout: timeout).flatMap({ $0.children(timeout: timeout) }) {
            if let item = menu.children(timeout: timeout).first(where: { $0.string("AXIdentifier") == identifier }) {
                return item
            }
        }
        return nil
    }

    /// An element of the dialog, by identifier: in the front window's sheet,
    /// else around the focused field, else in any window's sheet (the user
    /// may have gone to another Safari window, or another app, meanwhile).
    private static func find(_ identifier: String, in app: AXUIElement) -> AXUIElement? {
        let matches: (AXUIElement) -> Bool = { $0.string("AXIdentifier") == identifier }
        var roots: [AXUIElement] = []
        if let window = app.element(kAXFocusedWindowAttribute, timeout: timeout) { roots.append(window) }
        if let focused = app.element(kAXFocusedUIElementAttribute, timeout: timeout) {
            var node = focused
            for _ in 0..<parentDepth {
                guard let parent = node.element(kAXParentAttribute, timeout: timeout) else { break }
                if parent.string(kAXRoleAttribute) == "AXSheet" { roots.append(parent) }
                node = parent
            }
        }
        for root in roots + app.elements(kAXWindowsAttribute, timeout: timeout) {
            for sheet in [root] + root.children(timeout: timeout) where sheet.string(kAXRoleAttribute) == "AXSheet" {
                if let found = first(in: sheet, depth: 4, where: matches) { return found }
            }
        }
        return nil
    }

    private static func first(in element: AXUIElement, depth: Int, where matches: (AXUIElement) -> Bool) -> AXUIElement? {
        if matches(element) { return element }
        guard depth > 0 else { return nil }
        for child in element.children(timeout: timeout) {
            if let found = first(in: child, depth: depth - 1, where: matches) { return found }
        }
        return nil
    }
}
