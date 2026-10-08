import Foundation
import Testing
import AutoHushKit
@testable import WebAppPlayers

@Suite("Adding a web app", .serialized)
struct SafariWebAppMakerTests {
    @Test("what's typed becomes a web address, https added; anything else isn't one",
          arguments: [
            ("music.youtube.com", "https://music.youtube.com"),
            ("  https://open.spotify.com/ ", "https://open.spotify.com/"),
            ("http://localhost:8080/player", "http://localhost:8080/player"),
            ("music.amazon.es/?useHorizonte=true", "https://music.amazon.es/?useHorizonte=true"),
          ])
    func addresses(typed: String, expected: String) {
        #expect(WebAddress.url(from: typed)?.absoluteString == expected)
    }

    @Test("not web addresses", arguments: ["youtube music", "spotify", "ftp://files.example.com", "", "https://", ".com", "music."])
    func notAddresses(typed: String) {
        #expect(WebAddress.url(from: typed) == nil)
    }

    // MARK: - Asking the site

    private static func session(_ answers: [String: Int]) -> URLSession {
        StubProtocol.answers.withLock { $0 = answers }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test("any answer but “not found” means the site is there; a refused HEAD is asked again with GET")
    func answers() async throws {
        let url = URL(string: "https://music.example.com")!
        try await WebAddress.checkAnswers(url, session: Self.session(["HEAD": 200]))
        try await WebAddress.checkAnswers(url, session: Self.session(["HEAD": 403]))
        try await WebAddress.checkAnswers(url, session: Self.session(["HEAD": 405, "GET": 200]))
        await #expect(throws: WebAppMakingError.pageNotFound(host: "music.example.com")) {
            try await WebAddress.checkAnswers(url, session: Self.session(["HEAD": 404]))
        }
        await #expect(throws: WebAppMakingError.noAnswer(host: "music.example.com")) {
            try await WebAddress.checkAnswers(url, session: Self.session([:])) // no answer at all
        }
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
        let clock = TestClock()
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
                sleep: { [clock] in clock.advance($0) },
                clock: { [clock] in clock.now }
            )
        }

        /// Whether the user clicks Add to Dock (`false`: they cancel instead).
        let clicksAdd = Locked(true)
        let clicks = Locked(0)

        func make(_ address: String) async throws -> MadeWebApp {
            try await maker.makeWebApp(from: address, onStep: { [steps] in steps.append($0) }, confirmAdd: { [clicksAdd, clicks, safari] in
                clicks.withLock { $0 += 1 }
                safari.log.append("click Add to Dock")
                return clicksAdd.value
            })
        }
    }

    @Test("a new website is opened in Safari, added to the Dock, and the new web app returned")
    func makesOne() async throws {
        let setup = Setup()
        setup.safari.onAdd = { [installed = setup.installed] in installed.append(Self.made) }
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
        let start = setup.clock.now
        let made = try await setup.make("play.qobuz.com")
        #expect(setup.steps.value == [.checked, .opened, .siteAsks(shown: "consent.qobuz.com", site: "play.qobuz.com"),
                                      .readyToAdd(site: "play.qobuz.com"), .adding, .made(made)])
        #expect(setup.clock.now.timeIntervalSince(start) >= 2 * SafariWebAppMaker.siteCheckInterval)
        #expect(setup.clicks.value == 1)
    }

    @Test("nothing is added until the user clicks Add to Dock; cancelling instead adds nothing")
    func waitsForTheClick() async throws {
        let setup = Setup()
        setup.clicksAdd.withLock { $0 = false }
        await #expect(throws: CancellationError.self) { try await setup.make("play.qobuz.com") }
        #expect(!setup.safari.log.value.contains { $0.hasPrefix("add ") })
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
        let app = FileManager.default.temporaryDirectory.appending(path: "Sealed-\(UUID().uuidString)/Web.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: NSDictionary = ["CFBundleIdentifier": SafariWebApp.bundleIDPrefix + "TEST", "CFBundleName": "Web",
                                  "LSTemplateApplication": true]
        try info.write(to: contents.appending(path: "Info.plist"))
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

    @Test("cancelled while Safari's dialog is open, it cancels the dialog: nothing is added")
    func cancelled() async throws {
        let setup = Setup()
        setup.safari.holdsDialog = true
        setup.safari.onAdd = { [installed = setup.installed] in installed.append(Self.made) }
        let task = Task { try await setup.make("play.qobuz.com") }
        while !setup.safari.log.value.contains("add https://play.qobuz.com") { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(setup.safari.log.value.last == "cancel dialog")
        #expect(setup.installed.value == [Self.existing])
        #expect(setup.steps.value == [.checked, .opened, .readyToAdd(site: "play.qobuz.com"), .adding])
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

    @Test("Safari not loading the page, or no web app appearing after Add, is an error")
    func safariFails() async {
        let notLoading = Setup()
        notLoading.safari.loads = false
        await #expect(throws: WebAppMakingError.self) { try await notLoading.make("play.qobuz.com") }
        #expect(notLoading.safari.log.value == ["trusted", "open https://play.qobuz.com", "wait"])

        let nothingMade = Setup()
        await #expect(throws: WebAppMakingError.self) { try await nothingMade.make("play.qobuz.com") }
        #expect(nothingMade.clock.now.timeIntervalSince(TestClock().now) >= SafariWebAppMaker.appearTimeout)
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
    var loads = true
    var onAdd: (@Sendable () -> Void)?

    func isTrusted(prompt: Bool) async -> Bool { log.append("trusted"); return trusted }
    func open(_ url: URL) async -> Bool { log.append("open \(url.absoluteString)"); return true }
    /// The dialog stays open until the task is cancelled.
    var holdsDialog = false

    func waitForPage() async -> SafariTab? { log.append("wait"); return loads ? SafariTab(page: 1) : nil }
    /// The front page's address at each look, the last one staying; none:
    /// it can't be read.
    let pages = Locked<[URL]>([])
    func frontPageURL() async -> URL? {
        log.append("page")
        return pages.withLock { pages in
            defer { if pages.count > 1 { pages.removeFirst() } }
            return pages.first
        }
    }
    func addToDock(_ url: URL) async -> String? {
        log.append("add \(url.absoluteString)")
        while holdsDialog, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        guard !Task.isCancelled else {
            log.append("cancel dialog")
            return nil
        }
        onAdd?()
        return "Qobuz"
    }
    func closeTab(_ tab: SafariTab) async { log.append("close tab \(tab.page)") }
}

/// A value shared with closures.
final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { _value = value }
    var value: Value { lock.withLock { _value } }
    func append<Element>(_ element: Element) where Value == [Element] { lock.withLock { _value.append(element) } }
    func withLock<Result>(_ body: (inout Value) -> Result) -> Result { lock.withLock { body(&_value) } }
}

/// Answers each HTTP method with a status; a method without one gets no answer.
final class StubProtocol: URLProtocol {
    static let answers = OSAllocatedUnfairLockBox<[String: Int]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        guard let status = Self.answers.withLock({ $0[method] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// A lock around a value, for a class property.
final class OSAllocatedUnfairLockBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<T>(_ body: (inout Value) -> T) -> T { lock.withLock { body(&value) } }
}
