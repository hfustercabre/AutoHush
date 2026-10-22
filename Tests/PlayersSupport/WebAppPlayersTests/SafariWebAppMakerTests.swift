import Foundation
import Network
import Testing
@testable import AutoHushKit
@testable import WebAppPlayers
import AutoHushTestSupport

@Suite("Adding a web app")
struct SafariWebAppMakerTests {
    @Test("what's typed becomes a web address, https added; anything else isn't one",
          arguments: [
            ("music.youtube.com", "https://music.youtube.com"),
            ("  https://open.spotify.com/ ", "https://open.spotify.com/"),
            ("http://localhost:8080/player", "http://localhost:8080/player"),
            ("music.amazon.es/?useHorizonte=true", "https://music.amazon.es/?useHorizonte=true"),
            ("deezer.com/en/?redirect=https://www.deezer.com", "https://deezer.com/en/?redirect=https://www.deezer.com"),
          ])
    func addresses(typed: String, expected: String) {
        #expect(WebAddress.url(from: typed)?.absoluteString == expected)
    }

    @Test("not web addresses", arguments: ["youtube music", "spotify", "ftp://files.example.com", "", "https://", ".com", "music."])
    func notAddresses(typed: String) {
        #expect(WebAddress.url(from: typed) == nil)
    }

    // MARK: - Asking the site

    /// `host`'s site at an address of the asking test's own, so tests that
    /// run at once keep their answers apart (`session`).
    private static func site(_ host: String) -> URL { URL(string: "https://\(host)/?test=\(UUID().uuidString)")! }

    /// A session where `url` answers each HTTP method with `answers`.
    private static func session(_ answers: [String: Int], for url: URL) -> URLSession {
        StubProtocol.answers.withLock { $0[url] = answers }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test("any answer but “not found” means the site is there; a refused HEAD is asked again with GET")
    func answers() async throws {
        let url = Self.site("music.example.com")
        try await WebAddress.checkAnswers(url, session: Self.session(["HEAD": 200], for: url))
        try await WebAddress.checkAnswers(url, session: Self.session(["HEAD": 403], for: url))
        try await WebAddress.checkAnswers(url, session: Self.session(["HEAD": 405, "GET": 200], for: url))
        await #expect(throws: WebAppMakingError.pageNotFound(host: "music.example.com")) {
            try await WebAddress.checkAnswers(url, session: Self.session(["HEAD": 404], for: url))
        }
        await #expect(throws: WebAppMakingError.noAnswer(host: "music.example.com")) {
            try await WebAddress.checkAnswers(url, session: Self.session([:], for: url)) // no answer at all
        }
    }

    @Test("an http site, which App Transport Security keeps AutoHush from asking, answers when a connection to it opens (2026-10-19)")
    func plainHTTP() async throws {
        let url = URL(string: "http://radio.example.org:8000/live")!
        let tried = Locked<[URL]>([])
        let session = Self.session([:], for: url) // never asked
        try await WebAddress.checkAnswers(url, session: session, connects: { tried.append($0); return true })
        #expect(tried.value == [url])
        await #expect(throws: WebAppMakingError.noAnswer(host: "radio.example.org")) {
            try await WebAddress.checkAnswers(url, session: session, connects: { _ in false })
        }
        // https is asked as ever, without a connection check.
        let https = Self.site("music.example.com")
        try await WebAddress.checkAnswers(https, session: Self.session(["HEAD": 200], for: https),
                                          connects: { tried.append($0); return false })
        #expect(tried.value == [url])
    }

    @Test("an https site that sends AutoHush to http has answered: the redirect isn't followed, and App Transport Security's refusal counts as an answer")
    func redirectToHTTP() async throws {
        let toHTTP = URLRequest(url: URL(string: "http://radio.example.org/")!)
        let toHTTPS = URLRequest(url: URL(string: "https://www.example.com/")!)
        #expect(WebAddress.StopsAtPlainHTTP.follows(toHTTP) == nil)
        #expect(WebAddress.StopsAtPlainHTTP.follows(toHTTPS) == toHTTPS)
        let url = Self.site("radio.example.org")
        try await WebAddress.checkAnswers(url, session: Self.session(["HEAD": 301], for: url))
        try await WebAddress.checkAnswers(url, session: Self.session(["HEAD": URLError.appTransportSecurityRequiresSecureConnection.rawValue],
                                                                     for: url))
        await #expect(throws: WebAppMakingError.noAnswer(host: "radio.example.org")) {
            try await WebAddress.checkAnswers(url, session: Self.session(["HEAD": URLError.cannotConnectToHost.rawValue], for: url))
        }
    }

    @Test("a connection to an http site's host and port: open while something listens there, refused once nothing does")
    func connection() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let queue = DispatchQueue(label: "SafariWebAppMakerTests.listener")
        let port = Locked<UInt16?>(nil)
        listener.newConnectionHandler = { $0.cancel() }
        listener.stateUpdateHandler = { [port] state in
            if case .ready = state { port.withLock { $0 = listener.port?.rawValue } }
        }
        listener.start(queue: queue)
        await TestWait.until { port.value != nil }
        let listening = try #require(port.value)
        let site = URL(string: "http://localhost:\(listening)/")!
        #expect(await WebAddress.connects(to: site, timeout: 5))
        listener.cancel()
        try await Task.sleep(for: .milliseconds(200))
        #expect(await WebAddress.connects(to: site, timeout: 5) == false)
    }

    // MARK: - Making it

    private static let existing = SafariWebApp(bundleID: SafariWebApp.bundleIDPrefix + "YTM", name: "YT Music",
                                               url: URL(fileURLWithPath: "/Users/test/Applications/YT Music.app"),
                                               startURL: URL(string: "https://music.youtube.com/?source=pwa"))
    private static let made = SafariWebApp(bundleID: SafariWebApp.bundleIDPrefix + "NEW", name: "Qobuz",
                                           url: URL(fileURLWithPath: "/Users/test/Applications/Qobuz.app"),
                                           startURL: URL(string: "https://play.qobuz.com/"))

    private struct Setup {
        let safari = FakeSafari()
        let installed = Locked<[SafariWebApp]>([SafariWebAppMakerTests.existing])
        let steps = Locked<[WebAppMakingStep]>([])
        let checked = Locked<[URL]>([])
        var sameSite: @Sendable (SafariWebApp, URL) -> Bool = { $0.opens($1) }
        /// How many more looks a new app takes to be sealed.
        let unsealedLooks = Locked(0)
        let clock = ManualClock.webAppTests()
        /// The web apps a cancelled add quit and moved to the Trash.
        let discarded = Locked<[String]>([])
        var maker: SafariWebAppMaker {
            SafariWebAppMaker(
                safari: safari,
                webApps: { [installed] in installed.value },
                sameSite: sameSite,
                isSealed: { [unsealedLooks] _ in
                    unsealedLooks.withLock { looks in
                        defer { looks = max(0, looks - 1) }
                        return looks == 0
                    }
                },
                checkAnswers: { [checked] in checked.append($0) },
                discard: { [discarded] in discarded.append($0.bundleID) },
                sleep: { [clock] in clock.advance(by: $0) },
                clock: { [clock] in clock.now }
            )
        }

        /// Whether the user clicks Add to Dock (`false`: they cancel instead).
        let clicksAdd = Locked(true)
        let clicks = Locked(0)
        /// What happens as the user clicks Add to Dock, by the click's number.
        let onClick = Locked<(@Sendable (Int) -> Void)?>(nil)

        func make(_ address: String) async throws -> MadeWebApp {
            try await maker.makeWebApp(from: address, onStep: { [steps] in steps.append($0) },
                                       confirmAdd: { [clicksAdd, clicks, safari, onClick] in
                let click = clicks.withLock { $0 += 1; return $0 }
                safari.log.append("click Add to Dock")
                onClick.value?(click)
                return clicksAdd.value
            })
        }
    }

    @Test("a new website is opened in Safari, added to the Dock, and the new web app returned")
    func makesOne() async throws {
        let setup = Setup()
        setup.safari.onAdd = { [installed = setup.installed] in installed.append(Self.made) }
        setup.safari.frontTabPage.withLock { $0 = 3 } // the user's own tab of the site, gone to meanwhile
        let made = try await setup.make("play.qobuz.com")
        #expect(made == MadeWebApp(bundleID: Self.made.bundleID, name: "Qobuz", url: Self.made.url, alreadyThere: false))
        #expect(setup.checked.value == [URL(string: "https://play.qobuz.com")!])
        #expect(setup.safari.log.value == ["trusted", "open https://play.qobuz.com", "wait", "page", "click Add to Dock", "page",
                                           "add https://play.qobuz.com", "close tab 1"])
        #expect(setup.steps.value == [.checked, .opened, .readyToAdd(site: "play.qobuz.com"), .adding, .made(made)])
    }

    @Test("a site that asks something first on another of its hosts is waited for: added only once it shows, and the user clicks")
    func siteAsksFirst() async throws {
        let setup = Setup()
        setup.safari.pages.withLock {
            $0 = [URL(string: "https://consent.qobuz.com/m?continue=https://play.qobuz.com")!,
                  URL(string: "https://consent.qobuz.com/m?continue=https://play.qobuz.com")!,
                  URL(string: "https://play.qobuz.com/discover")!]
        }
        setup.safari.onAdd = { [installed = setup.installed] in installed.append(Self.made) }
        setup.safari.frontTabPage.withLock { $0 = 2 } // answering it loaded the site in the tab
        let start = setup.clock.now
        let made = try await setup.make("play.qobuz.com")
        #expect(setup.steps.value == [.checked, .opened, .siteAsks(shown: "consent.qobuz.com", site: "play.qobuz.com"),
                                      .readyToAdd(site: "play.qobuz.com"), .adding, .made(made)])
        #expect(setup.clock.now.timeIntervalSince(start) >= 2 * SafariWebAppMaker.siteCheckInterval)
        #expect(setup.clicks.value == 1)
        #expect(setup.safari.log.value.last == "close tab 2") // the tab the site then showed in
    }

    @Test("nothing is added until the user clicks Add to Dock; cancelling instead adds nothing and closes the tab it opened")
    func waitsForTheClick() async throws {
        let setup = Setup()
        setup.clicksAdd.withLock { $0 = false }
        await #expect(throws: CancellationError.self) { try await setup.make("play.qobuz.com") }
        #expect(!setup.safari.log.value.contains { $0.hasPrefix("add ") })
        #expect(setup.safari.log.value.last == "close tab 1" && setup.discarded.value.isEmpty)
        #expect(setup.steps.value == [.checked, .opened, .readyToAdd(site: "play.qobuz.com")])
    }

    @Test("if Safari left the site by the time the user clicks, it waits for the site again")
    func leftBeforeTheClick() async throws {
        let setup = Setup()
        setup.safari.pages.withLock {
            $0 = [URL(string: "https://play.qobuz.com")!, URL(string: "https://accounts.qobuz.com/login")!,
                  URL(string: "https://accounts.qobuz.com/login")!, URL(string: "https://play.qobuz.com")!]
        }
        setup.safari.onAdd = { [installed = setup.installed] in installed.append(Self.made) }
        _ = try await setup.make("play.qobuz.com")
        #expect(setup.clicks.value == 2)
        #expect(setup.steps.value.contains(.siteAsks(shown: "accounts.qobuz.com", site: "play.qobuz.com")))
    }

    @Test("the site itself: the same host with or without www, a part of a bare address, another country's site; not another host of the domain",
          arguments: [
            ("https://music.youtube.com", "https://music.youtube.com/watch?v=1", true),
            ("https://deezer.com", "https://www.deezer.com/en/", true),
            ("https://tidal.com", "https://listen.tidal.com/", true),
            ("https://music.amazon.com", "https://music.amazon.es/", true),
            ("https://music.amazon.com", "https://music.amazon.co.uk/", true),
            ("https://music.youtube.com", "https://consent.youtube.com/m?continue=x", false),
            ("https://open.spotify.com", "https://accounts.spotify.com/login", false),
            ("https://music.youtube.com", "about:blank", true),
            ("https://play.qobuz.com", "https://play.qobuz.com.example.net/", false),
            ("https://music.amazon.com", "https://music.amazon.evil.co/", false),
            ("https://music.amazon.com", "https://music.amazon.com.br/", true),
            ("https://music.amazon.com", "https://music.amazon.co/", true),
            ("https://music.amazon.de", "https://music.amazon.com/", true),
            ("https://radio.example.com", "https://radio.example.cat/", true),
            ("https://music.amazon.com", "https://music.amazon.bad.co/", false),
            ("https://music.amazon.com", "https://music.amazon.org/", false),
            ("http://192.168.1.10", "http://192.168.1.20/", false),
          ])
    func sameSite(typed: String, shown: String, expected: Bool) {
        #expect(WebAddress.isSameSite(URL(string: shown)!, as: URL(string: typed)!) == expected)
    }

    @Test("a new web app is returned only once Safari has sealed it: macOS won't open it before")
    func waitsForSeal() async throws {
        let setup = Setup()
        setup.unsealedLooks.withLock { $0 = 3 }
        setup.safari.onAdd = { [installed = setup.installed] in installed.append(Self.made) }
        let start = setup.clock.now
        let made = try await setup.make("play.qobuz.com")
        #expect(made.bundleID == Self.made.bundleID)
        #expect(setup.clock.now.timeIntervalSince(start) == 3 * SafariWebAppMaker.pollInterval)
    }

    @Test("a bundle is sealed once it's signed, as Safari does last")
    func sealed() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Sealed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = try TestAppBundle.make(in: folder, name: "Web", info: [
            "CFBundleIdentifier": SafariWebApp.bundleIDPrefix + "TEST", "CFBundleName": "Web", "LSTemplateApplication": true,
        ])
        #expect(!SafariWebApp.isSealed(at: app))

        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--sign", "-", app.path]
        try codesign.run()
        codesign.waitUntilExit()
        try #require(codesign.terminationStatus == 0)
        #expect(SafariWebApp.isSealed(at: app))
    }

    @Test("a website that already has a web app isn't added again")
    func alreadyThere() async throws {
        let setup = Setup()
        let made = try await setup.make("https://www.music.youtube.com/")
        #expect(made.alreadyThere)
        #expect(made.bundleID == Self.existing.bundleID)
        #expect(setup.safari.log.value.isEmpty)
        #expect(setup.steps.value == [.checked, .made(made)])
    }

    @Test("cancelled while Safari's dialog is open, it cancels the dialog: nothing is added, the tab it opened is closed")
    func cancelled() async throws {
        let setup = Setup()
        setup.safari.holdsDialog = true
        setup.safari.onAdd = { [installed = setup.installed] in installed.append(Self.made) }
        let task = Task { try await setup.make("play.qobuz.com") }
        defer { task.cancel() }
        await TestWait.until { setup.safari.log.value.contains("add https://play.qobuz.com") }
        try #require(setup.safari.log.value.contains("add https://play.qobuz.com"))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(setup.safari.log.value.suffix(2) == ["cancel dialog", "close tab 1"])
        #expect(setup.installed.value == [Self.existing] && setup.discarded.value.isEmpty)
        #expect(setup.steps.value == [.checked, .opened, .readyToAdd(site: "play.qobuz.com"), .adding])
    }

    @Test("cancelled once Add was clicked in Safari's dialog: the web app Safari makes all the same is quit and moved to the Trash, its tab closed")
    func cancelledAfterAdd() async throws {
        let setup = Setup()
        setup.unsealedLooks.withLock { $0 = 1 } // not sealed at the first look: AutoHush waits for it
        let task = Locked<Task<MadeWebApp, any Error>?>(nil)
        setup.safari.onAdd = { [installed = setup.installed] in
            installed.append(Self.made)
            task.value?.cancel() // the window's Cancel, just after Add in Safari's dialog
        }
        task.withLock { $0 = Task { try await setup.make("play.qobuz.com") } }
        let made = try #require(task.value)
        await #expect(throws: CancellationError.self) { try await made.value }
        #expect(setup.discarded.value == [Self.made.bundleID])
        #expect(setup.safari.log.value.last == "close tab 1")
    }

    @Test("another country's site of a tested service counts as the same: its web app is used")
    func sameService() async throws {
        var setup = Setup()
        let amazon = SafariWebApp(bundleID: SafariWebApp.bundleIDPrefix + "AMZ", name: "Amazon Music",
                                  url: URL(fileURLWithPath: "/Users/test/Applications/Amazon Music.app"),
                                  startURL: URL(string: "https://music.amazon.es/"))
        setup.installed.withLock { $0.append(amazon) }
        let tested = [TestedWebApp(name: "Amazon Music", address: "music.amazon.com", otherHosts: ["music.amazon.es"])]
        setup.sameSite = { TestedWebApp.sameSite($0, $1, tested: tested) }
        let made = try await setup.make("music.amazon.com")
        #expect(made.bundleID == amazon.bundleID)
        #expect(made.alreadyThere)
        #expect(setup.safari.log.value.isEmpty)
    }

    @Test("what isn't a web address is never looked up")
    func notAnAddress() async {
        let setup = Setup()
        await #expect(throws: WebAppMakingError.notAWebAddress) { try await setup.make("youtube music") }
        #expect(setup.checked.value.isEmpty)
        #expect(setup.safari.log.value.isEmpty)
    }

    @Test("without Accessibility, Safari isn't touched")
    func noAccessibility() async {
        let setup = Setup()
        setup.safari.trusted = false
        await #expect(throws: WebAppMakingError.accessibilityDenied) { try await setup.make("play.qobuz.com") }
        #expect(setup.safari.log.value == ["trusted"])
    }

    @Test("Safari not opening the address, not loading the page, or without its Add to Dock, is an error, each its own")
    func safariFails() async {
        let notOpening = Setup()
        notOpening.safari.opens = false
        await #expect(throws: WebAppMakingError.browserFailed("Safari couldn't open https://play.qobuz.com")) {
            try await notOpening.make("play.qobuz.com")
        }
        let notLoading = Setup()
        notLoading.safari.loads = false
        await #expect(throws: WebAppMakingError.browserFailed("the page didn't load in Safari")) { try await notLoading.make("play.qobuz.com") }
        #expect(notLoading.safari.log.value == ["trusted", "open https://play.qobuz.com", "wait"])
        let noAddToDock = Setup()
        noAddToDock.safari.addsToDock = false
        await #expect(throws: WebAppMakingError.browserFailed("Safari's Add to Dock wasn't available")) {
            try await noAddToDock.make("play.qobuz.com")
        }
        #expect(noAddToDock.steps.value.last == .adding)
    }

    @Test("Safari's dialog closed without adding: back to Add to Dock, whose next click opens it again")
    func closedWithoutAdding() async throws {
        let setup = Setup()
        setup.safari.adds.withLock { $0 = [false, true] }
        setup.safari.onAdd = { [installed = setup.installed] in installed.append(Self.made) }
        let start = setup.clock.now
        let made = try await setup.make("play.qobuz.com")
        #expect(setup.clicks.value == 2)
        #expect(setup.safari.log.value.filter { $0.hasPrefix("add ") }.count == 2)
        #expect(setup.steps.value == [.checked, .opened, .readyToAdd(site: "play.qobuz.com"), .adding, .notAdded,
                                      .readyToAdd(site: "play.qobuz.com"), .adding, .made(made)])
        #expect(setup.clock.now.timeIntervalSince(start) >= SafariWebAppMaker.appearTimeout)
    }

    @Test("a web app that comes after AutoHush stopped waiting is taken at the next Add to Dock: the dialog isn't opened again")
    func comesLate() async throws {
        let setup = Setup()
        setup.safari.adds.withLock { $0 = [false] }
        setup.onClick.withLock { onClick in
            onClick = { [installed = setup.installed] click in if click == 2 { installed.append(Self.made) } }
        }
        let made = try await setup.make("play.qobuz.com")
        #expect(made.bundleID == Self.made.bundleID)
        #expect(setup.safari.log.value.filter { $0.hasPrefix("add ") }.count == 1)
        #expect(setup.steps.value.suffix(3) == [.notAdded, .readyToAdd(site: "play.qobuz.com"), .made(made)])
    }

    @Test("a web app knows the website it opens, with or without www")
    func opens() {
        #expect(Self.existing.opens(URL(string: "https://music.youtube.com/watch?v=1")!))
        #expect(Self.existing.opens(URL(string: "https://www.music.youtube.com")!))
        #expect(!Self.existing.opens(URL(string: "https://youtube.com")!))
    }
}

/// Safari, in memory.
final class FakeSafari: SafariDriving, @unchecked Sendable {
    let log = Locked<[String]>([])
    var trusted = true
    /// Whether it opens an address, and has its Add to Dock (`false`: its menu item or dialog wasn't found).
    var opens = true
    var addsToDock = true
    var loads = true
    var onAdd: (@Sendable () -> Void)?

    func isTrusted(prompt: Bool) async -> Bool { log.append("trusted"); return trusted }
    func open(_ url: URL) async -> Bool { log.append("open \(url.absoluteString)"); return opens }
    /// The dialog stays open until the task is cancelled.
    var holdsDialog = false

    func waitForPage() async -> SafariTab? { log.append("wait"); return loads ? SafariTab(page: 1) : nil }
    /// The front page's address at each look, the last one staying; none:
    /// it can't be read.
    let pages = Locked<[URL]>([])
    /// The tab in front once the site shows after asking something: the same
    /// one, unless the test says the page changed (`frontTabPage`).
    let frontTabPage = Locked<Int>(1)
    func frontTab() async -> SafariTab? { log.append("front tab"); return SafariTab(page: frontTabPage.value) }

    func frontPageURL() async -> URL? {
        log.append("page")
        return pages.withLock { pages in
            defer { if pages.count > 1 { pages.removeFirst() } }
            return pages.first
        }
    }
    /// Whether each time the dialog opens the user clicks Add (`true`) or
    /// Cancel there; the last one stays.
    let adds = Locked<[Bool]>([true])

    func addToDock(_ url: URL) async -> AddToDockResult {
        log.append("add \(url.absoluteString)")
        guard addsToDock else { return .unavailable }
        while holdsDialog, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        guard !Task.isCancelled else {
            log.append("cancel dialog")
            return .cancelled
        }
        let added = adds.withLock { adds in
            defer { if adds.count > 1 { adds.removeFirst() } }
            return adds.first ?? true
        }
        if added { onAdd?() }
        return .closed
    }
    func closeTab(_ tab: SafariTab) async { log.append("close tab \(tab.page)") }
}

/// Answers each HTTP method with a status, by address; a method without one
/// gets no answer.
final class StubProtocol: URLProtocol {
    static let answers = Locked<[URL: [String: Int]]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        guard let url = request.url, let status = Self.answers.value[url]?[method] else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        // Below 0: that URLError instead of an answer.
        if status < 0 {
            client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue: status)))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
