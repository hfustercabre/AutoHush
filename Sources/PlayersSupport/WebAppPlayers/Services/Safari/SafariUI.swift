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
                      let tab = Self.frontTab(in: app)
                else { return nil }
                return tab
            }
            if let tab { return tab }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return nil
    }

    package func frontTab() async -> SafariTab? {
        await Self.queue.run {
            guard let app = Self.safariElement() else { return nil }
            return Self.frontTab(in: app)
        }
    }

    package func frontPageURL() async -> URL? {
        await Self.queue.run {
            guard let app = Self.safariElement(), let page = Self.frontPage(in: app) else { return nil }
            return page.value(kAXURLAttribute) as? URL
        }
    }

    package func addToDock(_ url: URL, dialogShown: @escaping @Sendable (CGRect) -> Void) async -> AddToDockResult {
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
        // Where it shows, so AutoHush's window can move off it.
        if let frame = await Self.queue.run({ () -> CGRect? in
            guard let app = Self.safariElement(), let button = Self.find("AddToDockFormAddButton", in: app) else { return nil }
            return Self.sheet(around: button)?.frame
        }) {
            dialogShown(frame)
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
        let closed = await Self.queue.run { () -> TabClosing in
            guard let app = Self.safariElement(), let front = Self.readFront(in: app), tab.isSame(as: front.tab) else {
                return .notInFront
            }
            let closeTab = Self.menuItem("CloseTab", in: app)
            guard let press = Self.closingPress(closeTabEnabled: closeTab?.value(kAXEnabledAttribute) as? Bool,
                                                otherTabs: front.bar.mayHoldOtherTabs) else {
                return front.bar == .unreadable ? .unreadable : .withheld
            }
            guard let item = press == .closeTab ? closeTab : Self.menuItem("CloseWindow", in: app) else { return .failed }
            // Read again right before the press, which acts on whatever is
            // in front then: the user may have gone to another window or tab
            // meanwhile (L1 of 1.4.3's diff review).
            guard Self.stillInFront(front, in: app) else { return .notInFront }
            return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success ? .closed : .failed
        }
        switch closed {
        case .notInFront: logger.notice("The tab Add a Web App opened isn’t in front any more: left open")
        case .withheld: logger.notice("Safari’s Close Tab is off in a window of several tabs: the tab Add a Web App opened was left open")
        case .unreadable: logger.notice("Safari’s tab bar couldn’t be read: the window of the tab Add a Web App opened was left open")
        case .failed: logger.error("Safari’s Close Tab wasn’t found or didn’t take: the tab Add a Web App opened was left open")
        case .closed: break
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

    /// The front window's tab (`SafariTab`): the window, its selected tab
    /// button and its page. A page loading in the tab keeps the window and
    /// the button, its page becoming another element (measured on macOS 27
    /// and on 14.4's Safari 17.4, 2026-11-18). The button is read from the
    /// window's tab bar (`tabBar`); its page isn't walked for it. A window of
    /// one tab shows no button (Separate tab layout; Compact shows one): its
    /// page tells it (the diff review's R1), and still does once a second tab
    /// adds the tab bar (C-1 of 1.4.3's review; both measured on macOS 27,
    /// 2026-11-19).
    private static func frontTab(in app: AXUIElement) -> SafariTab? { readFront(in: app)?.tab }

    /// The front window's tab as read, with what `closeTab` needs of it.
    private struct FrontTab {
        let tab: SafariTab
        let window: AXUIElement
        let button: AXUIElement?
        let bar: TabBar
    }

    private static func readFront(in app: AXUIElement) -> FrontTab? {
        guard let window = app.element(kAXFocusedWindowAttribute, timeout: timeout) else { return nil }
        let (bar, buttons) = tabBar(in: window)
        let button = buttons.first { ($0.value(kAXValueAttribute) as? NSNumber)?.boolValue == true }
        let tab = SafariTab(window: AnyHashable(window), button: button.map { AnyHashable($0) },
                            page: frontPage(in: app).map { AnyHashable($0) })
        return FrontTab(tab: tab, window: window, button: button, bar: bar)
    }

    /// Whether `front` is still the tab in front: its window focused, its
    /// button (when it has one) still selected, or a window read without a
    /// tab bar still without one (a tab the user opened with ⌘T meanwhile
    /// would go with Close Window: D2 of the diff review). A few reads, so
    /// the press follows them at once.
    private static func stillInFront(_ front: FrontTab, in app: AXUIElement) -> Bool {
        guard let window = app.element(kAXFocusedWindowAttribute, timeout: timeout), CFEqual(window, front.window) else { return false }
        guard let button = front.button else { return tabBar(in: window).bar == front.bar }
        return (button.value(kAXValueAttribute) as? NSNumber)?.boolValue == true
    }

    /// A window's tab bar, as read: Safari puts its tab buttons right in a
    /// group, the buttons 2 to 5 levels under the window, so the group 1 to
    /// 4 (measured 2026-11-19: on macOS 27 an AXOpaqueProviderGroup, buttons
    /// at 2 in the Separate layout, 4 in Compact, a level more in full
    /// screen; on 14.4's Safari 17.4 an AXGroup, buttons at 2). Only the
    /// first such group's buttons count, never another selected tab button
    /// elsewhere in the window (C-4 of 1.4.3's review).
    enum TabBar: Equatable {
        /// None: a window of one tab, in Safari's Separate tab layout.
        case absent
        /// A read on the way failed (Safari busy): unknown.
        case unreadable
        /// Its tab buttons, as many.
        case tabs(Int)

        /// Whether the window may hold tabs besides the one in front: also
        /// when that's unknown (I2 of 1.4.3's diff review), so its window is
        /// never closed for it.
        var mayHoldOtherTabs: Bool {
            switch self {
            case .absent: false
            case .unreadable: true
            case .tabs(let count): count > 1
            }
        }
    }

    private static func tabBar(in window: AXUIElement) -> (bar: TabBar, buttons: [AXUIElement]) {
        // A read Safari didn't answer makes it unreadable, whichever it was:
        // a role, a subrole or children (D3 of the diff review).
        var failed = false
        func search(_ element: AXUIElement, _ depth: Int) throws(AXReadFailed) -> [AXUIElement]? {
            let role = try element.readString(kAXRoleAttribute)
            guard role != "AXWebArea" else { return nil }
            let isCandidate = role.map(tabBarRoles.contains) ?? false
            // At the last level only a candidate's children are read (D1).
            guard depth > 0 || isCandidate else { return nil }
            let children = try element.readChildren(timeout: timeout)
            if isCandidate {
                var buttons: [AXUIElement] = []
                for child in children {
                    if try child.readString(kAXSubroleAttribute) == "AXTabButton" { buttons.append(child) }
                }
                if !buttons.isEmpty { return buttons }
            }
            guard depth > 0 else { return nil }
            for child in children {
                do {
                    if let found = try search(child, depth - 1) { return found }
                } catch {
                    failed = true
                }
            }
            return nil
        }
        do {
            if let buttons = try search(window, tabBarDepth) { return (.tabs(buttons.count), buttons) }
        } catch {
            failed = true
        }
        return (failed ? .unreadable : .absent, [])
    }

    /// How deep under the window the tab bar's group is looked for: one
    /// level more than measured (4, Compact in full screen).
    private static let tabBarDepth = 5

    /// The roles of the group holding the tab buttons, as measured.
    private static let tabBarRoles: Set<String> = ["AXOpaqueProviderGroup", "AXGroup"]

    /// What closes the tab in front: Close Tab, or Close Window when Safari
    /// disables Close Tab for a window's only tab (measured on macOS 27, in
    /// both tab layouts: Compact shows that tab's button, Separate none).
    /// Close Tab disabled in a window of several tabs (not that case: a
    /// pinned tab, say) closes nothing, never the window with the user's
    /// other tabs (C-3 of 1.4.3's review).
    enum ClosingPress: Equatable { case closeTab, closeWindow }

    static func closingPress(closeTabEnabled: Bool?, otherTabs: Bool) -> ClosingPress? {
        guard closeTabEnabled == false else { return .closeTab }
        return otherTabs ? nil : .closeWindow
    }


    private enum TabClosing { case notInFront, withheld, unreadable, failed, closed }

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

    /// The sheet `element` is in: the dialog.
    private static func sheet(around element: AXUIElement) -> AXUIElement? {
        var node = element
        for _ in 0..<parentDepth {
            guard let parent = node.element(kAXParentAttribute, timeout: timeout) else { return nil }
            if parent.string(kAXRoleAttribute) == "AXSheet" { return parent }
            node = parent
        }
        return nil
    }

    private static func first(in element: AXUIElement, depth: Int, skipping skippedRole: String? = nil,
                              where matches: (AXUIElement) -> Bool) -> AXUIElement? {
        if matches(element) { return element }
        guard depth > 0 else { return nil }
        if let skippedRole, element.string(kAXRoleAttribute) == skippedRole { return nil }
        for child in element.children(timeout: timeout) {
            if let found = first(in: child, depth: depth - 1, skipping: skippedRole, where: matches) { return found }
        }
        return nil
    }
}
