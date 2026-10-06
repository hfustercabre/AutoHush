import AppKit
import ApplicationServices
import OSLog
import AutoHushKit

/// Makes a Safari web app from an address, the way a person does: it opens
/// the website in Safari and uses Safari's own File → Add to Dock, then
/// clicks Add (keeping the name Safari suggests). Nothing else is created or
/// changed; macOS has no other way to make one.
///
/// A website that already has a web app isn't added again: that one is used.
package final class SafariWebAppMaker: WebAppMaking {
    /// How long the new web app may take to appear after Add.
    static let appearTimeout: TimeInterval = 20
    static let pollInterval: TimeInterval = 0.25

    private let safari: any SafariDriving
    private let webApps: @Sendable () -> [SafariWebApp]
    private let isSealed: @Sendable (URL) -> Bool
    private let checkAnswers: @Sendable (URL) async throws -> Void
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let clock: @Sendable () -> Date
    private let logger = Logger(category: "WebAppPlayer")

    package init(
        safari: any SafariDriving = SafariUI(),
        webApps: @escaping @Sendable () -> [SafariWebApp] = { SafariWebAppFinder().webApps() },
        isSealed: @escaping @Sendable (URL) -> Bool = { SafariWebApp.isSealed(at: $0) },
        checkAnswers: @escaping @Sendable (URL) async throws -> Void = { try await WebAddress.checkAnswers($0) },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.safari = safari
        self.webApps = webApps
        self.isSealed = isSealed
        self.checkAnswers = checkAnswers
        self.sleep = sleep
        self.clock = clock
    }

    package func makeWebApp(from address: String, onStep: @escaping @Sendable (WebAppMakingStep) -> Void) async throws -> MadeWebApp {
        guard let url = WebAddress.url(from: address) else { throw WebAppMakingError.notAWebAddress }
        try await checkAnswers(url)
        onStep(.checked)

        if let existing = webApps().first(where: { $0.opens(url) }) {
            let made = MadeWebApp(bundleID: existing.bundleID, name: existing.name, url: existing.url, alreadyThere: true)
            onStep(.made(made))
            return made
        }
        guard await safari.isTrusted(prompt: true) else { throw WebAppMakingError.accessibilityDenied }

        let before = Set(webApps().map(\.bundleID))
        guard await safari.open(url) else { throw WebAppMakingError.browserFailed("Safari couldn't open \(url.absoluteString)") }
        guard await safari.waitForPage() else { throw WebAppMakingError.browserFailed("the page didn't load in Safari") }
        onStep(.opened)

        guard let suggested = await safari.addToDock(url) else {
            throw WebAppMakingError.browserFailed("Safari's Add to Dock wasn't available")
        }
        logger.notice("Added a web app in Safari (suggested name: \(suggested, privacy: .private))")
        let deadline = clock().addingTimeInterval(Self.appearTimeout)
        while clock() < deadline {
            // Safari seals the new app last: it can't be opened before.
            if let app = webApps().first(where: { !before.contains($0.bundleID) }), isSealed(app.url) {
                // Launch Services may learn of it only later: AutoHush looks
                // apps up there to tell they're installed.
                LSRegisterURL(app.url as CFURL, true)
                let made = MadeWebApp(bundleID: app.bundleID, name: app.name, url: app.url, alreadyThere: false)
                onStep(.made(made))
                return made
            }
            await sleep(Self.pollInterval)
        }
        throw WebAppMakingError.browserFailed("no complete web app appeared after Add")
    }
}

/// What `SafariWebAppMaker` does in Safari. A protocol, so tests stand in.
package protocol SafariDriving: Sendable {
    func isTrusted(prompt: Bool) async -> Bool
    /// Opens the address in Safari, in front; `false` when it couldn't.
    func open(_ url: URL) async -> Bool
    /// Waits until the page in Safari's front window has loaded and can be
    /// added; `false` after a while.
    func waitForPage() async -> Bool
    /// Chooses File → Add to Dock, makes sure the dialog has `url` (the page
    /// may have moved), and clicks Add. Returns the name Safari suggested;
    /// `nil` when the dialog didn't come.
    func addToDock(_ url: URL) async -> String?
}

/// Safari, driven through Accessibility. Its menu item and the dialog's
/// fields and buttons are found by their identifiers, the same in every
/// language (measured on macOS 27): `AddToDock`, `AddToDockFormNameTextField`,
/// `AddToDockFormURLTextField`, `AddToDockFormAddButton`.
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

    package func waitForPage() async -> Bool {
        try? await Task.sleep(for: .seconds(Self.settleTime))
        let deadline = Date().addingTimeInterval(Self.pageTimeout)
        while Date() < deadline {
            if let app = Self.safariElement(), Self.pageLoaded(in: app),
               let item = Self.menuItem("AddToDock", in: app), Self.value(kAXEnabledAttribute, of: item) as? Bool == true {
                return true
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return false
    }

    package func addToDock(_ url: URL) async -> String? {
        guard let app = Self.safariElement() else {
            logger.error("Add to Dock: Safari isn't running")
            return nil
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
                let name = Self.find("AddToDockFormNameTextField", in: app)
                    .flatMap { Self.value(kAXValueAttribute, of: $0) as? String } ?? ""
                if let field = Self.find("AddToDockFormURLTextField", in: app) {
                    let shown = (Self.value(kAXValueAttribute, of: field) as? String).flatMap(URL.init(string:))
                    if shown.flatMap({ $0.host() }).map(WebAddress.siteHost) != url.host().map(WebAddress.siteHost) {
                        AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, url.absoluteString as CFString)
                    }
                }
                try? await Task.sleep(for: .seconds(Self.iconTime))
                guard AXUIElementPerformAction(add, kAXPressAction as CFString) == .success else { return nil }
                return name
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        logger.error("Add to Dock: Safari's dialog didn't come within \(Int(Self.dialogTimeout), privacy: .public) s")
        return nil
    }

    // MARK: - Accessibility

    private static func safariElement() -> AXUIElement? {
        guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { !$0.isTerminated })
        else { return nil }
        let app = AXUIElementCreateApplication(safari.processIdentifier)
        AXUIElementSetMessagingTimeout(app, timeout)
        return app
    }

    /// The front window's page has loaded (Safari's browser view says so in
    /// its identifier, e.g. "BrowserView?IsPageLoaded=true&…").
    private static func pageLoaded(in app: AXUIElement) -> Bool {
        guard let window = element(kAXFocusedWindowAttribute, of: app) else { return false }
        return first(in: window, depth: 6) {
            (value("AXIdentifier", of: $0) as? String)?.contains("IsPageLoaded=true") == true
        } != nil
    }

    private static func menuItem(_ identifier: String, in app: AXUIElement) -> AXUIElement? {
        guard let bar = element(kAXMenuBarAttribute, of: app) else { return nil }
        for menu in children(of: bar).flatMap(children(of:)) {
            if let item = children(of: menu).first(where: { value("AXIdentifier", of: $0) as? String == identifier }) {
                return item
            }
        }
        return nil
    }

    /// An element of the dialog, by identifier: in the front window's sheet,
    /// else around the focused field.
    private static func find(_ identifier: String, in app: AXUIElement) -> AXUIElement? {
        let matches: (AXUIElement) -> Bool = { value("AXIdentifier", of: $0) as? String == identifier }
        var roots: [AXUIElement] = []
        if let window = element(kAXFocusedWindowAttribute, of: app) { roots.append(window) }
        if let focused = element(kAXFocusedUIElementAttribute, of: app) {
            var node = focused
            while let parent = element(kAXParentAttribute, of: node) {
                if value(kAXRoleAttribute, of: parent) as? String == "AXSheet" { roots.append(parent) }
                node = parent
            }
        }
        for root in roots {
            for sheet in [root] + children(of: root) where value(kAXRoleAttribute, of: sheet) as? String == "AXSheet" {
                if let found = first(in: sheet, depth: 4, where: matches) { return found }
            }
        }
        return nil
    }

    private static func first(in element: AXUIElement, depth: Int, where matches: (AXUIElement) -> Bool) -> AXUIElement? {
        if matches(element) { return element }
        guard depth > 0 else { return nil }
        for child in children(of: element) {
            if let found = first(in: child, depth: depth - 1, where: matches) { return found }
        }
        return nil
    }

    private static func value(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = value(attribute, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (value(kAXChildrenAttribute, of: element) as? [AnyObject] ?? []).compactMap { child in
            CFGetTypeID(child) == AXUIElementGetTypeID() ? (child as! AXUIElement) : nil
        }
    }
}
