import AppKit
import CheckedPlayers
import Foundation
import os
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("AppDelegate")
struct AppDelegateTests {
    /// In-memory preferences, the choices kept beside them in a suite of its
    /// own, the apps added with Add an App in memory, and a downloads folder
    /// of its own, so tests never write AutoHush's preference files or touch
    /// its real Caches. Two stand-in music players to choose from, which may
    /// be controlled, which of them are installed (the second in a folder
    /// inside /Applications), folder watches the test fires, and monitorings
    /// that stand in for the engine, so a start never taps real audio processes.
    @MainActor
    private final class Scratch {
        var preferences = Preferences(store: InMemoryPreferenceStore())
        private let suite = TestDefaults("AppDelegateTests")
        lazy var defaults = suite.defaults
        let addedSetups = SetupsInMemory()
        lazy var checkedPlayers = CheckedPlayers(store: addedSetups, locate: { _ in nil })
        let launchAtLogin = MockLaunchAtLoginController(isEnabled: false)
        let downloads = FileManager.default.temporaryDirectory.appending(path: "AppDelegateTests-\(UUID().uuidString)")
        let notifier = MockUpdateNotifier()
        let first = MockMusicPlayer(bundleID: Players.first, name: "First")
        let second = MockMusicPlayer(bundleID: Players.second, name: "Second", canFade: false)
        let monitorings = FakeMonitorings()
        /// The Mac's outputs, muted for a check, and its volume, lowered for the music.
        let outputs = MockOutputMuting()
        let volume = MockSystemVolume([0: -10])
        /// The menu bar's Now Playing setting, shown for a press and hidden again.
        let nowPlaying = NowPlayingInMemory()
        lazy var players = MusicPlayerCatalog(players: [first, second], formerDefault: Players.first)
        var installed: Set<String> = [Players.first, Players.second]
        let chooser = FakePlayerChooser()
        let learningWindow = FakeLearningWindow()
        /// How many learning windows AutoHush made (each Learn Again makes a new one).
        var learningWindowsMade = 0
        let addWindow = FakeAddWebAppWindow()
        var maker = FakeWebAppMaker(.failure(.notAWebAddress))
        var opened: [URL] = []
        /// The permissions as the stand-in system reports them, and what was asked of it.
        var trusted = true
        var automationStatus: OSStatus = noErr
        var running: Set<String> = []
        var audio: AudioCapturePermission? = .granted
        var asked: [String] = []
        /// Holds the Automation queries while closed, as a busy player does.
        let automationGate = AutomationGate()
        lazy var permissionCenter = PermissionCenter(system: .init(
            isTrusted: { [unowned self] in self.trusted },
            promptAccessibility: { [unowned self] in self.asked.append("prompt accessibility") },
            automation: { [status = automationStatus, gate = automationGate] _, ask in
                await gate.pass()
                return ask ? noErr : status
            },
            runningPID: { [unowned self] in self.running.contains($0) ? 4242 : nil },
            audio: { [unowned self] in self.audio },
            requestAudio: { [unowned self] _ in self.asked.append("ask audio") },
            openPane: { [unowned self] in self.asked.append("open \($0.rawValue)") }
        ))

        private var onFolderChange: (@MainActor () -> Void)?

        func locate(_ bundleID: String) -> URL? {
            guard installed.contains(bundleID) else { return nil }
            let folder = bundleID == Players.second ? "/Applications/Players" : "/Applications"
            return URL(fileURLWithPath: "\(folder)/\(bundleID).app")
        }

        func watch(_: URL, onChange: @escaping @MainActor () -> Void) -> AnyObject? {
            onFolderChange = onChange
            return NSObject()
        }

        func changeFolder() {
            onFolderChange?()
        }

        deinit {
            try? FileManager.default.removeItem(at: downloads)
            suite.remove()
        }
    }

    private enum Players {
        static let first = "com.example.first"
        static let second = "com.example.second"
    }

    /// `chosenPlayer`: the player already chosen before this launch, if any.
    /// Returns the monitorings its starts made, too.
    @MainActor
    private func makeSUT(
        _ scratch: Scratch = Scratch(),
        chosenPlayer: String? = Players.first,
        updateChecker: UpdateChecker = UpdateChecker { _ in throw URLError(.notConnectedToInternet) },
        updateInstaller: MockUpdateInstaller = MockUpdateInstaller(),
        windowWatchSleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        madeWebAppWait: Duration = .zero
    ) -> (AppDelegate, FakeMonitorings) {
        if let chosenPlayer { scratch.preferences.musicPlayer = chosenPlayer }
        let sut = AppDelegate(
            preferences: scratch.preferences,
            defaults: scratch.defaults,
            launchAtLoginController: scratch.launchAtLogin,
            updateChecker: updateChecker,
            updateInstaller: updateInstaller,
            updateNotifier: scratch.notifier,
            updateDownloadsFolder: scratch.downloads,
            players: scratch.players,
            checkedPlayers: scratch.checkedPlayers,
            checkOutputMute: OutputMute(outputs: scratch.outputs, defaults: scratch.defaults),
            volumeLeveler: SystemVolumeLeveler(volume: scratch.volume, defaults: scratch.defaults, sleep: { _ in }),
            nowPlayingDefaults: scratch.defaults,
            nowPlayingSetting: scratch.nowPlaying.setting,
            makeMonitoring: scratch.monitorings.make,
            locateApp: { scratch.locate($0) },
            makePlayerChooser: { _ in scratch.chooser },
            makeLearningWindow: { _ in
                scratch.learningWindowsMade += 1
                return scratch.learningWindow
            },
            webAppMaker: scratch.maker,
            makeAddWebAppWindow: { _, _ in scratch.addWindow },
            openApp: { scratch.opened.append($0) },
            learnedWindowDelay: .zero,
            madeWebAppWait: madeWebAppWait,
            currentVersion: AppVersion("0.2.0"),
            retries: PlayerSession.Retries(permissionInterval: 0.05, delays: 0.02...0.08),
            watchFolder: { scratch.watch($0, onChange: $1) },
            installCheckDelay: .zero,
            permissionCenter: scratch.permissionCenter,
            windowWatchSleep: windowWatchSleep
        )
        return (sut, scratch.monitorings)
    }

    /// Starts monitoring the chosen player, as at launch, and waits until it runs.
    @MainActor
    private func start(_ sut: AppDelegate) async {
        sut.session.launch()
        await TestWait.until { sut.status.health == .ready }
    }

    // MARK: - Players that learn

    @MainActor
    private func waitFor(sourceLocation: SourceLocation = #_sourceLocation, _ condition: @MainActor () -> Bool) async {
        await TestWait.until(sourceLocation: sourceLocation, condition)
    }

    @MainActor
    @Test("choosing a web app AutoHush must learn asks for it in a window, which shows the steps and closes once learned")
    func learningWindow() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                        status: .learning(hasPlayed: false))
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch)
        #expect(sut.status.learning == nil)
        #expect(sut.status.playerOptions.map(\.kind) == [.app, .safariWebApp])

        sut.chooseMusicPlayer(webApp.bundleID)
        #expect(scratch.learningWindow.isOpen)
        #expect(sut.status.learning == .learning(hasPlayed: false))
        #expect(sut.settingsModel.learning == .learning(hasPlayed: false))

        webApp.set(.learning(hasPlayed: true))
        await waitFor { sut.settingsModel.learning == .learning(hasPlayed: true) }
        #expect(sut.settingsModel.learning == .learning(hasPlayed: true))

        webApp.set(.learned)
        await waitFor { !scratch.learningWindow.isOpen }
        #expect(!scratch.learningWindow.isOpen)
        #expect(sut.status.learning == .learned)
        #expect(!scratch.learningWindow.isOpen && sut.status.canLearnControlsAgain)

        sut.chooseMusicPlayer(Players.first)
        #expect(sut.status.learning == nil)
        sut.chooseMusicPlayer(webApp.bundleID) // learned already: no window
        #expect(scratch.learningWindow.shownCount == 1)
    }

    @MainActor
    @Test("a web app's controls are learned afresh in a new window, which replaces an open one; closed before It's Playing, what it learned stays")
    func learnControlsAgain() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music", status: .learned)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch)
        sut.chooseMusicPlayer(webApp.bundleID)
        await waitFor { sut.status.learning == .learned }
        #expect(!scratch.learningWindow.isOpen)
        #expect(sut.status.canLearnControlsAgain)
        #expect(sut.settingsModel.canLearnControlsAgain)

        sut.learnControlsAgain()
        await waitFor { scratch.learningWindow.isOpen && sut.status.learning == .relearning }
        #expect(webApp.learnAgainCount == 1)
        #expect(scratch.learningWindowsMade == 1)
        #expect(sut.status.canLearnControlsAgain)
        #expect(sut.settingsModel.learning == .relearning) // still learned: the Controls row says so

        // Later, or the close button, before It's Playing: what it learned stays.
        scratch.learningWindow.close()
        await waitFor { sut.status.learning == .learned }
        #expect(webApp.keepLearnedCount == 1)

        // Again, and It's Playing taken (the player forgets then); then again
        // while the window is open: it closes, a new one starts over, and
        // closing the old one keeps nothing.
        sut.learnControlsAgain()
        await waitFor { scratch.learningWindow.isOpen && sut.status.learning == .relearning }
        webApp.set(.learning(hasPlayed: true))
        await waitFor { sut.settingsModel.learning == .learning(hasPlayed: true) }
        sut.learnControlsAgain()
        #expect(!scratch.learningWindow.isOpen) // the old one, closed at once
        // The new window and the player's new status come by separate tasks, in either order.
        await waitFor { scratch.learningWindow.isOpen && sut.settingsModel.learning == .learning(hasPlayed: false) }
        #expect(webApp.learnAgainCount == 3)
        #expect(scratch.learningWindowsMade == 3)
        #expect(webApp.keepLearnedCount == 1)
        #expect(sut.settingsModel.learning == .learning(hasPlayed: false))

        sut.chooseMusicPlayer(Players.first) // a player that learns nothing
        #expect(!sut.status.canLearnControlsAgain)
        #expect(!sut.settingsModel.canLearnControlsAgain)
    }

    @MainActor
    @Test("learning a web app's controls opens it when it isn't running, as adding it does; a running one is left as it is")
    func learningOpensWebApp() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music", status: .learned)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch)
        sut.chooseMusicPlayer(webApp.bundleID)
        await waitFor { sut.status.learning == .learned }
        #expect(scratch.opened.isEmpty)

        sut.learnControlsAgain()
        await waitFor { scratch.learningWindow.isOpen && scratch.opened.count == 1 }
        #expect(scratch.opened.count == 1)

        scratch.learningWindow.close()
        scratch.running.insert(webApp.bundleID)
        sut.learnControlsAgain()
        await waitFor { scratch.learningWindow.isOpen }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(scratch.opened.count == 1) // running: not opened again
    }

    @MainActor
    @Test("learning again closes Add a Web App, which floats in the same corner, whatever its step")
    func learnAgainClosesAdd() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music", status: .learned)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch)
        sut.chooseMusicPlayer(webApp.bundleID)
        await waitFor { sut.status.learning == .learned }
        sut.showAddWebApp() // another site's address being typed
        #expect(scratch.addWindow.isOpen)

        sut.learnControlsAgain()
        #expect(!scratch.addWindow.isOpen)
        await waitFor { scratch.learningWindow.isOpen }
        #expect(scratch.learningWindow.isOpen)
    }

    @MainActor
    @Test("learning again, the window closed while the web app's button was missing still keeps what it learned")
    func keepLearnedWhileButtonMissing() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music", status: .learned)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch)
        sut.chooseMusicPlayer(webApp.bundleID)
        await waitFor { sut.status.learning == .learned }
        sut.learnControlsAgain()
        await waitFor { scratch.learningWindow.isOpen && sut.status.learning == .relearning }

        webApp.set(.learning(hasPlayed: false)) // its button went missing meanwhile
        await waitFor { sut.status.learning == .learning(hasPlayed: false) }
        scratch.learningWindow.close() // Later
        await waitFor { webApp.keepLearnedCount == 1 }
        #expect(webApp.keepLearnedCount == 1) // the player decides: it was learning again
    }

    @MainActor
    @Test("while a permission is missing, the learning window asks for it first, and the card's Controls row stays")
    func learningWaitsForPermission() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                        status: .learning(hasPlayed: false))
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch)

        sut.chooseMusicPlayer(webApp.bundleID)
        await waitFor { sut.status.health == .needsPermission(.accessibility(player: "YT Music")) }
        #expect(scratch.learningWindow.isOpen) // with the permission as its first step
        #expect(sut.status.canLearnControlsAgain) // the card's Controls row stays

        webApp.setFailVerify(nil) // allowed: the retry starts monitoring
        await waitFor { sut.status.health == .ready }
        #expect(sut.settingsModel.learning == .learning(hasPlayed: false))
        #expect(scratch.learningWindow.shownCount == 1)
    }

    @MainActor
    @Test("a web app that isn't running yet still opens the learning window, which says to play it")
    func learningWindowForPlayerNotRunning() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                        status: .learning(hasPlayed: false))
        webApp.setFailVerify(.playerNotRunning)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch)

        sut.chooseMusicPlayer(webApp.bundleID)
        await waitFor { sut.status.health == .degraded("YT Music isn’t running") }
        #expect(scratch.learningWindow.isOpen)
    }

    @MainActor
    @Test("a web app added from its address is chosen and opened, its steps shown in the add window, which closes once learned")
    func addWebApp() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.NEW", name: "Qobuz", status: .learning(hasPlayed: false))
        let found = FoundPlayers()
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { found.players })
        scratch.installed.insert(webApp.bundleID)
        let appURL = URL(fileURLWithPath: "/Users/test/Applications/Qobuz.app")
        scratch.maker = FakeWebAppMaker(.success(MadeWebApp(bundleID: webApp.bundleID, name: "Qobuz", url: appURL, alreadyThere: false)))
        scratch.maker.onMake = { found.players = [webApp] }
        let (sut, _) = makeSUT(scratch)

        sut.showAddWebApp()
        #expect(scratch.addWindow.isOpen)
        sut.addWebAppModel.address = "play.qobuz.com"
        sut.addWebAppModel.continueTapped()
        await waitFor { sut.addWebAppModel.phase == .readyToAdd(site: "play.qobuz.com") }
        #expect(found.players.isEmpty) // nothing's added before the user clicks Add to Dock
        sut.addWebAppModel.addTapped()
        await waitFor { sut.status.chosenPlayerID == webApp.bundleID && !scratch.opened.isEmpty }
        #expect(sut.status.chosenPlayerID == webApp.bundleID)
        #expect(sut.addWebAppModel.phase == .learning(name: "Qobuz", alreadyThere: false))
        #expect(scratch.opened == [appURL])
        #expect(!scratch.learningWindow.isOpen) // the add window shows the steps

        webApp.set(.learned)
        await waitFor { !scratch.addWindow.isOpen }
        #expect(!scratch.addWindow.isOpen)
    }

    /// What the user does while the add window says the web app made isn't found.
    enum WhileNotFound: CaseIterable, Sendable {
        case nothing, addressChanged, windowClosed
    }

    @MainActor
    @Test("a web app made but not listed yet is looked for a few times; still missing, the add window says so and Continue tries again; once listed, it's added by itself, unless the address was changed or the window closed meanwhile",
          arguments: WhileNotFound.allCases)
    func addedWebAppNotFound(meanwhile: WhileNotFound) async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.NEW", name: "Qobuz", status: .learning(hasPlayed: false))
        let found = FoundPlayers() // macOS doesn't list it
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { found.players })
        scratch.installed.insert(webApp.bundleID)
        let appURL = URL(fileURLWithPath: "/Users/test/Applications/Qobuz.app")
        scratch.maker = FakeWebAppMaker(.success(MadeWebApp(bundleID: webApp.bundleID, name: "Qobuz", url: appURL, alreadyThere: false)))
        let (sut, _) = makeSUT(scratch)

        sut.openAddWebApp() // the menu's Add a Web App…
        sut.addWebAppModel.address = "play.qobuz.com"
        sut.addWebAppModel.continueTapped()
        await waitFor { sut.addWebAppModel.phase == .readyToAdd(site: "play.qobuz.com") }
        sut.addWebAppModel.addTapped()
        await waitFor { sut.addWebAppModel.problem != nil }
        #expect(sut.addWebAppModel.problem == .notFound(name: "Qobuz"))
        #expect(sut.addWebAppModel.phase == .entering)
        #expect(sut.addWebAppModel.address == "play.qobuz.com") // Continue tries again
        #expect(sut.status.chosenPlayerID != webApp.bundleID)
        #expect(scratch.addWindow.isOpen)

        switch meanwhile {
        case .nothing: break
        case .addressChanged: sut.addWebAppModel.address = "deezer.com"
        case .windowClosed: scratch.addWindow.close()
        }
        // Once macOS lists it, it's added again by itself, which finds it there and chooses it.
        found.players = [webApp]
        scratch.maker.result = .success(MadeWebApp(bundleID: webApp.bundleID, name: "Qobuz", url: appURL, alreadyThere: true))
        sut.refreshPlayerOptions() // as the window watch does each second meanwhile
        guard meanwhile == .nothing else {
            #expect(sut.webAppAwaitingListing == nil) // no longer looked for
            sut.refreshPlayerOptions()
            await sut.session.waitUntilIdle()
            #expect(sut.status.chosenPlayerID == Players.first)
            #expect(sut.addWebAppModel.problem == .notFound(name: "Qobuz"))
            return
        }
        await waitFor { sut.status.chosenPlayerID == webApp.bundleID }
        #expect(sut.addWebAppModel.problem == nil)
        #expect(sut.addWebAppModel.phase == .learning(name: "Qobuz", alreadyThere: true))
    }

    @MainActor
    @Test("a player chosen while a web app just made is looked for stays chosen, and nothing says the web app is missing")
    func playerChosenWhileLookingForWebApp() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.NEW", name: "Qobuz", status: .learning(hasPlayed: false))
        let found = FoundPlayers() // macOS doesn't list it
        scratch.players = MusicPlayerCatalog(players: [scratch.first, scratch.second], found: { found.players })
        scratch.installed.insert(webApp.bundleID)
        let appURL = URL(fileURLWithPath: "/Users/test/Applications/Qobuz.app")
        scratch.maker = FakeWebAppMaker(.success(MadeWebApp(bundleID: webApp.bundleID, name: "Qobuz", url: appURL, alreadyThere: true)))
        let (sut, _) = makeSUT(scratch, madeWebAppWait: .milliseconds(30))

        sut.showAddWebApp()
        sut.addWebAppModel.address = "play.qobuz.com"
        sut.addWebAppModel.continueTapped()
        await waitFor { sut.addWebAppModel.madeBundleID == webApp.bundleID }
        sut.chooseMusicPlayer(Players.second) // from the menu, meanwhile
        await waitFor { sut.addingWebApp == nil }
        #expect(sut.status.chosenPlayerID == Players.second)
        #expect(sut.addWebAppModel.problem == nil)
    }

    @MainActor
    @Test("added from the welcome window, the add window closes: the welcome window asks for what it needs, and learning follows its Done")
    func addWebAppFromWelcome() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.NEW", name: "Qobuz", status: .learning(hasPlayed: false))
        let found = FoundPlayers()
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { found.players })
        scratch.installed = [Players.first, webApp.bundleID]
        let appURL = URL(fileURLWithPath: "/Users/test/Applications/Qobuz.app")
        scratch.maker = FakeWebAppMaker(.success(MadeWebApp(bundleID: webApp.bundleID, name: "Qobuz", url: appURL, alreadyThere: false)))
        scratch.maker.onMake = { found.players = [webApp] }
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first) // brings the welcome window
        #expect(sut.isShowingPlayerChooser)

        sut.showAddWebApp()
        sut.addWebAppModel.address = "play.qobuz.com"
        sut.addWebAppModel.continueTapped()
        await waitFor { sut.addWebAppModel.phase == .readyToAdd(site: "play.qobuz.com") }
        sut.addWebAppModel.addTapped()
        await waitFor { sut.status.chosenPlayerID == webApp.bundleID && !scratch.addWindow.isOpen }
        #expect(!scratch.addWindow.isOpen) // one window asks: the welcome window
        #expect(sut.isShowingPlayerChooser)
        #expect(sut.settingsModel.welcomeAsksPermissions)
        #expect(!scratch.learningWindow.isOpen)

        sut.finishWelcome()
        #expect(scratch.learningWindow.isOpen)
    }

    @MainActor
    @Test("a suggested web app opens the add window filled in with its address, and the player stays")
    func suggestedWebApp() {
        let scratch = Scratch()
        scratch.players = MusicPlayerCatalog(players: [scratch.first], suggested: {
            [WebAppSuggestion(name: "Deezer", address: "deezer.com")]
        })
        let (sut, _) = makeSUT(scratch)
        let suggestion = PlayerOption.suggestionID("deezer.com")
        #expect(sut.status.playerOptions.contains { $0.bundleID == suggestion && $0.webAddress == "deezer.com" })

        sut.chooseMusicPlayer(suggestion)
        #expect(scratch.addWindow.isOpen)
        #expect(sut.addWebAppModel.address == "deezer.com")
        #expect(sut.addWebAppModel.phase == .entering)
        #expect(sut.status.chosenPlayerID == Players.first)

        sut.addWebAppModel.address = "something else"
        sut.showAddWebApp() // the window's open: what's typed stays
        #expect(sut.addWebAppModel.address == "something else")
        sut.chooseMusicPlayer(suggestion) // another click fills it in again
        #expect(sut.addWebAppModel.address == "deezer.com")
    }

    @MainActor
    @Test("a web app made moments ago is chosen from where it was found, before macOS knows it")
    func addWebAppFoundWhereMade() async {
        let scratch = Scratch()
        let appURL = URL(fileURLWithPath: "/Users/test/Applications/Qobuz.app")
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.NEW", name: "Qobuz", status: .learned,
                                        installedURL: appURL)
        let found = FoundPlayers()
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { found.players })
        scratch.maker = FakeWebAppMaker(.success(MadeWebApp(bundleID: webApp.bundleID, name: "Qobuz", url: appURL,
                                                            alreadyThere: false)))
        scratch.maker.onMake = { found.players = [webApp] }
        let (sut, _) = makeSUT(scratch)
        sut.showAddWebApp()
        sut.addWebAppModel.address = "play.qobuz.com"
        sut.addWebAppModel.continueTapped()
        await waitFor { sut.addWebAppModel.phase == .readyToAdd(site: "play.qobuz.com") }
        sut.addWebAppModel.addTapped()
        await waitFor { sut.status.chosenPlayerID == webApp.bundleID }
        #expect(sut.status.chosenPlayerID == webApp.bundleID) // not in `scratch.installed`: macOS doesn't know it
        #expect(sut.status.playerOptions.first { $0.bundleID == webApp.bundleID }?.appURL == appURL)
    }

    @MainActor
    @Test("closing the add window while it waits for Add to Dock cancels it: nothing is added")
    func addWebAppClosedBeforeTheClick() async {
        let scratch = Scratch()
        scratch.maker = FakeWebAppMaker(.success(MadeWebApp(bundleID: "x", name: "X", url: URL(fileURLWithPath: "/x.app"),
                                                            alreadyThere: false)))
        let made = OSAllocatedUnfairLock(initialState: false)
        scratch.maker.onMake = { made.withLock { $0 = true } }
        let (sut, _) = makeSUT(scratch)
        sut.showAddWebApp()
        sut.addWebAppModel.address = "play.qobuz.com"
        sut.addWebAppModel.continueTapped()
        await waitFor { sut.addWebAppModel.phase == .readyToAdd(site: "play.qobuz.com") }
        let adding = sut.addingWebApp
        sut.addWebAppModel.windowClosed()
        #expect(sut.addWebAppModel.phase == .entering)
        await adding?.value // the cancelled add is over
        #expect(!made.withLock { $0 })
        #expect(scratch.opened.isEmpty)
    }

    @MainActor
    @Test("closing the add window while it adds cancels it; the next add isn't held up")
    func addWebAppCancelled() async {
        let scratch = Scratch()
        scratch.maker = FakeWebAppMaker(.failure(.notAWebAddress))
        scratch.maker.result = .success(MadeWebApp(bundleID: "x", name: "X", url: URL(fileURLWithPath: "/x.app"), alreadyThere: false))
        scratch.maker.waitsForCancel = true
        let (sut, _) = makeSUT(scratch)
        sut.showAddWebApp()
        sut.addWebAppModel.address = "play.qobuz.com"
        sut.addWebAppModel.continueTapped()
        await waitFor { sut.addWebAppModel.phase == .opening }
        #expect(sut.addWebAppModel.phase == .opening)

        sut.addWebAppModel.windowClosed() // the window's Cancel, or its close button
        #expect(sut.addWebAppModel.phase == .entering)
        await waitFor { scratch.maker.wasCancelled }
        #expect(scratch.maker.wasCancelled)
        #expect(scratch.opened.isEmpty)
        #expect(sut.status.chosenPlayerID == Players.first)

        scratch.maker.waitsForCancel = false
        scratch.maker.result = .failure(.noAnswer(host: "play.qobuz.com"))
        sut.showAddWebApp()
        sut.addWebAppModel.address = "play.qobuz.com"
        sut.addWebAppModel.continueTapped()
        await waitFor { sut.addWebAppModel.problem != nil }
        #expect(sut.addWebAppModel.problem == .noAnswer(host: "play.qobuz.com"))
    }

    @MainActor
    @Test("adding the web app already chosen and learned just closes the window")
    func addWebAppAlreadyChosen() async {
        let scratch = Scratch()
        let appURL = URL(fileURLWithPath: "/Users/test/Applications/Qobuz.app")
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.NEW", name: "Qobuz", status: .learned,
                                        installedURL: appURL)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.maker = FakeWebAppMaker(.success(MadeWebApp(bundleID: webApp.bundleID, name: "Qobuz", url: appURL,
                                                            alreadyThere: true)))
        let (sut, _) = makeSUT(scratch, chosenPlayer: webApp.bundleID)
        #expect(sut.status.chosenPlayerID == webApp.bundleID)
        sut.showAddWebApp()
        sut.addWebAppModel.address = "play.qobuz.com"
        sut.addWebAppModel.continueTapped()
        await waitFor { !scratch.addWindow.isOpen }
        #expect(!scratch.addWindow.isOpen)
    }

    @MainActor
    @Test("the learned buttons of deleted web apps are forgotten; installed ones' are kept")
    func forgetsDeletedWebApps() {
        let scratch = Scratch()
        let appURL = URL(fileURLWithPath: "/Users/test/Applications/Qobuz.app")
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.KEPT", name: "Qobuz", status: .learned,
                                        installedURL: appURL)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        let store = InMemoryPreferenceStore()
        store.set([webApp.bundleID: ["play": "Play"], "com.apple.Safari.WebApp.GONE-\(UUID())": ["play": "Play"]],
                  forKey: Preferences.webAppButtonsKey)
        scratch.preferences = Preferences(store: store)
        _ = makeSUT(scratch)
        let kept = store.object(forKey: Preferences.webAppButtonsKey) as? [String: Any]
        #expect(kept.map { Array($0.keys) } == [webApp.bundleID])
    }

    @MainActor
    @Test("a web app that can't be added says why, and keeps the address to try again")
    func addWebAppFails() async {
        let scratch = Scratch()
        scratch.maker = FakeWebAppMaker(.failure(.noAnswer(host: "nowhere.example")))
        let (sut, _) = makeSUT(scratch)
        sut.showAddWebApp()
        sut.addWebAppModel.address = "nowhere.example"
        sut.addWebAppModel.continueTapped()
        await waitFor { sut.addWebAppModel.problem != nil }
        #expect(sut.addWebAppModel.problem == .noAnswer(host: "nowhere.example"))
        #expect(sut.addWebAppModel.phase == .entering)
        #expect(sut.addWebAppModel.address == "nowhere.example")
        #expect(sut.addWebAppModel.problemText?.contains("nowhere.example") == true)
        #expect(sut.status.chosenPlayerID == Players.first)
    }

    @MainActor
    @Test("a chosen web app that's deleted is no longer chosen: no Controls row, the status line asks for a player, and the welcome window opens")
    func chosenWebAppDeleted() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.DELETED-\(UUID())", name: "Spotify",
                                        status: .learning(hasPlayed: false),
                                        installedURL: URL(fileURLWithPath: "/Users/test/Applications/Spotify.app"))
        let found = FoundPlayers()
        found.players = [webApp]
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { found.players })
        let (sut, _) = makeSUT(scratch, chosenPlayer: webApp.bundleID)
        #expect(sut.status.chosenPlayerID == webApp.bundleID)
        #expect(sut.status.canLearnControlsAgain)

        found.players = [] // moved to the Trash, or deleted
        scratch.changeFolder()
        await waitFor { sut.status.chosenPlayerID == nil }
        #expect(sut.status.chosenPlayerID == nil)
        #expect(!sut.status.canLearnControlsAgain)
        #expect(sut.settingsModel.chosenPlayer == nil)
        #expect(scratch.preferences.musicPlayer == nil)
        #expect(sut.status.health == .waitingForPlayer)
        #expect(scratch.chooser.isOpen)
    }

    @MainActor
    @Test("a web app chosen earlier and not learned yet is offered to learn at launch, without opening the window")
    func learningAtLaunch() {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                        status: .learning(hasPlayed: false))
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch, chosenPlayer: webApp.bundleID)
        #expect(sut.status.canLearnControlsAgain && sut.settingsModel.learning == .learning(hasPlayed: false))
        #expect(!scratch.learningWindow.isOpen)
    }

    @MainActor
    @Test("another app's launch, or one without a bundle identifier, doesn't change the health or start again",
          arguments: ["org.videolan.vlc", nil] as [String?])
    func otherAppLaunchDoesNothing(bundleID: String?) async {
        let (sut, monitorings) = makeSUT()
        await start(sut)

        sut.handleApplicationDidLaunch(bundleIdentifier: bundleID)
        await sut.session.waitUntilIdle()
        #expect(sut.status.health == .ready)
        #expect(monitorings.made.count == 1)
    }

    @MainActor
    @Test("the chosen player's launch sets app back to starting and starts it again")
    func playerLaunchSetsStartingState() async {
        let scratch = Scratch()
        await scratch.first.setFailVerify(MusicPlayerError.playerNotRunning)
        let (sut, monitorings) = makeSUT(scratch)
        sut.session.launch()
        await waitFor { sut.status.health == .degraded("First isn’t running") }

        await scratch.first.setFailVerify(nil)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first)
        #expect(sut.status.health == .starting)
        await waitFor { sut.status.health == .ready }
        #expect(monitorings.made.count == 2) // the one listing the apps while it was closed, then its own
        #expect(monitorings.made[0].isStopped && !monitorings.made[1].isStopped)
    }

    @MainActor
    @Test("an app that plays only the volume sound (BetterDisplay) is ignored once it runs; others aren't")
    func volumeSoundAppsIgnored() async {
        let (sut, monitorings) = makeSUT()
        await start(sut)
        let betterDisplay = AudioSource(id: "pro.betterdisplay.BetterDisplay", name: "BetterDisplay")
        sut.ignoreVolumeSoundApps([betterDisplay, AudioSource(id: "org.videolan.vlc", name: "VLC")])
        #expect(sut.userSettings.state.ignoredApps.map(\.id) == [betterDisplay.id])
        #expect(sut.status.ignoredApps.map(\.id) == [betterDisplay.id]) // in the menu's Ignored Apps
        #expect(monitorings.made[0].ignored == [betterDisplay.id]) // the monitoring ignores it
    }

    @MainActor
    @Test("macOS's notices reach AutoHush: the chosen player opening starts it again, an app that plays only the volume sound opening is ignored, the Mac sleeping and waking (or only its screens) reach the session; once AutoHush quits, a launch does nothing")
    func workspaceNotices() async throws {
        let scratch = Scratch()
        await scratch.first.setFailVerify(MusicPlayerError.playerNotRunning)
        let (sut, monitorings) = makeSUT(scratch)
        sut.session.launch()
        await waitFor { sut.status.health == .degraded("First isn’t running") }
        sut.registerPlayerLaunchObserver()
        let observer = sut.playerLaunchObserver
        sut.registerPlayerLaunchObserver() // once only
        #expect(observer != nil && sut.playerLaunchObserver === observer)
        sut.registerSleepObservers()
        let center = NSWorkspace.shared.notificationCenter
        func launch(_ app: FakeRunningApplication) {
            center.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil,
                        userInfo: [NSWorkspace.applicationUserInfoKey: app])
        }

        await scratch.first.setFailVerify(nil)
        launch(FakeRunningApplication(bundleID: Players.first))
        await waitFor { sut.status.health == .ready }
        #expect(monitorings.made.count == 2) // the one listing the apps while it was closed, then its own

        // BetterDisplay opened (an app on the disk: a running app's bundle names it).
        let folder = FileManager.default.temporaryDirectory.appending(path: "AppDelegateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let betterDisplay = folder.appending(path: "BetterDisplay.app")
        try FileManager.default.createDirectory(at: betterDisplay.appending(path: "Contents"), withIntermediateDirectories: true)
        try (["CFBundleIdentifier": "pro.betterdisplay.BetterDisplay"] as NSDictionary)
            .write(to: betterDisplay.appending(path: "Contents/Info.plist"))
        launch(FakeRunningApplication(bundleID: "pro.betterdisplay.BetterDisplay", bundleURL: betterDisplay))
        await waitFor { !sut.userSettings.state.ignoredApps.isEmpty }
        #expect(sut.userSettings.state.ignoredApps.map(\.id) == ["pro.betterdisplay.BetterDisplay"])

        for (notice, asleep) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false),
                                 (NSWorkspace.willSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            center.post(name: notice, object: nil)
            await waitFor { sut.session.isAsleep == asleep }
        }
        #expect(monitorings.made.last?.asleep == [true, false, true, false])

        sut.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(sut.playerLaunchObserver == nil && sut.sleepObservers.isEmpty)
        launch(FakeRunningApplication(bundleID: Players.first))
        await Task.yield() // what a notice still observed would start
        await sut.session.waitUntilIdle()
        #expect(monitorings.made.count == 2) // not started again
    }

    // MARK: - A player opened without what it needs

    @MainActor
    @Test("a player opened without the option it needs: one to reopen always is reopened at once, but found so again within a minute only the card says so; its Reopen reopens it; any other is left to the card, or, just chosen, asked about: Cancel leaves it so, Reopen with the box ticked reopens it from then on")
    func playerNeedingReopen() async {
        let scratch = Scratch()
        let tunes = MockMusicPlayer(bundleID: "com.example.tunes", name: "Tunes")
        let radio = MockMusicPlayer(bundleID: "com.example.radio", name: "Radio")
        await tunes.setNeedsReopening(true, afterReopen: true) // a launcher that drops the option
        await radio.setNeedsReopening(true)
        scratch.players = MusicPlayerCatalog(players: [tunes, radio])
        scratch.installed = [tunes.bundleID, radio.bundleID]
        // The alert's box ticked for Tunes. As at launch, AutoHush reopened no
        // player yet (a run of this test before, in this process, did).
        ReopenChoices.setReopensAlways(tunes.bundleID, defaults: scratch.defaults)
        AppDelegate.lastReopens = [:]

        // Reopened at once; found so again right after, it isn't quit and
        // reopened over and over.
        let (sut, _) = makeSUT(scratch, chosenPlayer: tunes.bundleID)
        await waitFor { sut.status.playerNeedsReopen }
        #expect(await tunes.reopenCount == 1)
        sut.handleApplicationDidLaunch(bundleIdentifier: tunes.bundleID)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await tunes.reopenCount == 1)
        #expect(sut.status.playerNeedsReopen)
        // Found so again over a minute later, it's reopened by itself again.
        AppDelegate.now = { Date().addingTimeInterval(61) }
        defer { AppDelegate.now = Date.init }
        sut.handleApplicationDidLaunch(bundleIdentifier: tunes.bundleID)
        await TestWait.until { await tunes.reopenCount == 2 }
        #expect(await tunes.reopenCount == 2)

        await tunes.setNeedsReopening(true)
        sut.reopenChosenPlayer() // the card's Reopen
        await waitFor { !sut.status.playerNeedsReopen }
        #expect(!sut.status.playerNeedsReopen)
        #expect(await tunes.reopenCount == 3)

        sut.chooseMusicPlayer(radio.bundleID, asksToReopen: false) // not asked: reopening it was just skipped in Add an App
        await waitFor { sut.status.playerNeedsReopen }
        #expect(await radio.reopenCount == 0)

        // Asked when one is chosen: Reopen (Return) or Cancel (Escape), and the box.
        let alert = AppDelegate.reopenAlert("Radio")
        #expect(alert.messageText == "Reopen Radio?")
        #expect(alert.buttons.map(\.title) == ["Reopen Radio", "Cancel"])
        #expect(alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1b}"])
        #expect(alert.showsSuppressionButton && alert.suppressionButton?.title == "Always reopen Radio this way")

        // Cancel leaves it to the card, the box ticked or not; Reopen with the
        // box ticked reopens it, and from then on without asking.
        let shown = CallLog()
        sut.runAlert = { alert in
            shown.calls.append(alert.messageText)
            alert.suppressionButton?.state = .on
            return shown.calls.count == 1 ? .alertSecondButtonReturn : .alertFirstButtonReturn
        }
        sut.chooseMusicPlayer(radio.bundleID, replacing: true) // checked again in Add an App, and used
        await waitFor { shown.calls.count == 1 }
        #expect(await radio.reopenCount == 0)
        #expect(sut.status.playerNeedsReopen)
        #expect(!ReopenChoices.reopensAlways(radio.bundleID, defaults: scratch.defaults))

        sut.chooseMusicPlayer(radio.bundleID, replacing: true)
        await TestWait.until { await radio.reopenCount == 1 }
        await waitFor { !sut.status.playerNeedsReopen }
        #expect(!sut.status.playerNeedsReopen)
        #expect(shown.calls == ["Reopen Radio?", "Reopen Radio?"])
        #expect(ReopenChoices.reopensAlways(radio.bundleID, defaults: scratch.defaults))
    }

    // MARK: - Apps added with Add an App

    @MainActor
    @Test("Add an App's Use keeps what the check found and chooses the app, again once checked again (its new setup used, asking to reopen it as told); Remove asks first: Cancel keeps it; Remove forgets it, and the chosen app lets go of its app, none is chosen and the welcome window asks; one not chosen just leaves the list")
    func addedAppUsedAndRemoved() async throws {
        let scratch = Scratch()
        let added = AddedApps(scratch.addedSetups, needReopening: true)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { added.players() })
        scratch.installed.formUnion(["com.example.added", "com.example.kept"])
        func result(_ id: String, _ name: String, menu: String) -> CheckResult {
            CheckResult(ways: [CheckResult.WayResult(kind: .menu, mark: .works)],
                        setup: PlayerSetup(bundleID: id, name: name, appURL: URL(fileURLWithPath: "/Applications/\(id).app"),
                                           ways: [.menu(menuName: menu)]))
        }
        scratch.addedSetups.save(try #require(result("com.example.kept", "Kept", menu: "Controls").setup)) // added before
        let (sut, _) = makeSUT(scratch)
        let alerts = CallLog()
        // Reopen Added?: Cancel. Remove Added?: Cancel, then Remove. Remove Kept?: Remove.
        let answers: [NSApplication.ModalResponse] = [.alertSecondButtonReturn, .alertSecondButtonReturn,
                                                      .alertFirstButtonReturn, .alertFirstButtonReturn]
        sut.runAlert = { alert in
            alerts.calls.append(alert.messageText + (alert.informativeText.hasPrefix("It’s your current player") ? " (chosen)" : ""))
            return alerts.calls.count <= answers.count ? answers[alerts.calls.count - 1] : .alertSecondButtonReturn
        }

        // Used right after Skip in its Reopen step: chosen, and not asked to reopen it.
        sut.useCheckedApp(result("com.example.added", "Added", menu: "Controls"), asksToReopen: false)
        #expect(scratch.addedSetups.setups().map(\.bundleID) == ["com.example.added", "com.example.kept"])
        #expect(sut.status.playerOptions.filter { $0.kind == .checkedApp }.map(\.name) == ["Added", "Kept"])
        #expect(sut.player?.bundleID == "com.example.added")
        await waitFor { sut.status.playerNeedsReopen }
        let used = try #require(added.player("com.example.added"))

        // Checked again while chosen: chosen again with its new setup, the
        // player it replaces lets go of its app, and reopening is asked.
        sut.useCheckedApp(result("com.example.added", "Added", menu: "Playback"), asksToReopen: true)
        let usedAgain = try #require(added.player("com.example.added"))
        #expect(usedAgain !== used && sut.player.map { $0 as AnyObject } === usedAgain)
        await waitFor { alerts.calls.count == 1 }
        await TestWait.until { await used.releases == 1 }
        #expect(await used.releases == 1)

        // Remove Added… (its row with Option held), while it's chosen, as Add an App kept its check.
        ReopenChoices.setReopensAlways("com.example.added", defaults: scratch.defaults)
        let kept = KeptCheckStore(defaults: scratch.defaults)
        kept.save(KeptCheck(app: CheckableApp(bundleID: "com.example.added", name: "Added", url: URL(fileURLWithPath: "/Applications/com.example.added.app")),
                            result: result("com.example.added", "Added", menu: "Playback"), at: Date()))
        sut.removeAddedApp("com.example.added")
        await waitFor { alerts.calls.count == 2 }
        #expect(sut.player?.bundleID == "com.example.added" && scratch.addedSetups.setups().count == 2) // Cancel

        sut.removeAddedApp("com.example.added")
        await waitFor { alerts.calls.count == 3 }
        #expect(sut.player == nil && scratch.preferences.musicPlayer == nil)
        #expect(scratch.chooser.isOpen) // none is chosen: the welcome window asks
        #expect(scratch.addedSetups.setups().map(\.bundleID) == ["com.example.kept"])
        #expect(sut.status.playerOptions.filter { $0.kind == .checkedApp }.map(\.name) == ["Kept"])
        #expect(!ReopenChoices.reopensAlways("com.example.added", defaults: scratch.defaults))
        #expect(kept.load() == nil)
        await TestWait.until { await usedAgain.releases == 1 }
        #expect(await usedAgain.releases == 1) // its mute or switch back off

        sut.removeAddedApp("com.example.kept")
        await waitFor { alerts.calls.count == 4 }
        #expect(scratch.addedSetups.setups().isEmpty)
        #expect(!sut.status.playerOptions.contains { $0.kind == .checkedApp })
        #expect(alerts.calls == ["Reopen Added?", "Remove Added? (chosen)", "Remove Added? (chosen)", "Remove Kept?"])
        let keptPlayer = try #require(added.player("com.example.kept"))
        #expect(await keptPlayer.releases == 0) // not chosen: nothing to let go of
    }

    @MainActor
    @Test("Add an App opens at its first step, or as it is while it's open, with the same model and window; its list of apps and the warning before the check open in windows of their own, a new warning replacing the last, which mutes the app only with Audio Recording allowed outside AntiDot mode, else the Mac's sound, if its output can be muted; its Start starts the check")
    func addAppWindows() async throws {
        let (sut, _) = makeSUT()
        let world = World()
        world.playing = true
        var services = world.services
        // As AutoHush's own services hand these over.
        services.showChooser = { [weak sut] in sut?.showAppChooser() }
        services.showWarning = { [weak sut] in sut?.showCheckWarning() }
        let model = AddAppModel(services: services)
        sut.addAppModel = model

        sut.showAddApp()
        let window = try #require(sut.addAppWindow)
        #expect(window.isOpen && sut.addAppModel === model)
        await waitFor { !model.apps.isEmpty } // read at its first step
        sut.showCheckWarning() // no app chosen yet: no warning
        #expect(sut.checkWarningWindow == nil)

        model.openChooser()
        let chooser = try #require(sut.appChooserWindow)
        #expect(chooser.isOpen)
        model.choose(world.apps[0])
        await waitFor { model.stage == .ready }
        sut.showAddApp() // open: shown as it is
        #expect(model.stage == .ready && sut.addAppWindow === window)

        model.continueToCheck()
        let warning = try #require(sut.checkWarningWindow)
        let warningView = try #require(warning.window?.contentViewController as? NSHostingController<CheckWarningView>)
        #expect(warning.isOpen && warningView.rootView.muting == .app)
        world.antiDot = true
        model.continueToCheck()
        let macMuted = try #require(sut.checkWarningWindow)
        let macMutedView = try #require(macMuted.window?.contentViewController as? NSHostingController<CheckWarningView>)
        await waitFor { !warning.isOpen }
        #expect(macMuted !== warning && macMuted.isOpen && macMutedView.rootView.muting == .mac)
        world.macCanMute = false
        model.continueToCheck()
        let unmuted = try #require(sut.checkWarningWindow)
        let unmutedView = try #require(unmuted.window?.contentViewController as? NSHostingController<CheckWarningView>)
        await waitFor { !macMuted.isOpen }
        #expect(unmuted.isOpen && unmutedView.rootView.muting == .none)

        unmutedView.rootView.start()
        await waitFor { world.runs == 1 }
        #expect(model.stage == .checking && !unmuted.isOpen)

        // Closed (the check stops), then opened again: from its first step.
        window.close()
        chooser.close()
        await waitFor { !window.isOpen }
        sut.showAddApp()
        #expect(sut.addAppWindow === window && window.isOpen && model.stage == .choosing && model.chosen == nil)
        window.close()
    }

    @MainActor
    @Test("a check that can't mute only its app (AntiDot mode, or no Audio Recording) mutes the Mac's output while it runs, never one that taps the app's own sound; the output is put back as the check ends, as it stops, as AutoHush quits, and at the next launch after a crash during one")
    func checkMutesTheMac() async {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let world = World()
        world.playing = true
        // AutoHush's own start and end of a check, around the stand-in check.
        let live = sut.liveAddAppServices()
        var services = world.services
        services.macCanMute = live.macCanMute
        services.checkStarted = live.checkStarted
        services.checkEnded = live.checkEnded
        let model = AddAppModel(services: services)
        sut.addAppModel = model
        model.reset()
        await model.loadApps()
        model.choose(world.apps[0])
        await waitFor { model.stage == .ready }
        func check() async {
            world.run = FakeCheckRun()
            let runs = world.runs
            model.startCheck()
            await waitFor { world.runs == runs + 1 }
        }
        func checkAgain() async {
            model.checkAgain()
            await waitFor { model.stage == .ready }
        }
        let muted = { scratch.outputs.mutes[7] == true }

        #expect(model.checkMuting == .app) // its own sound tapped: the Mac's is left alone
        await check()
        #expect(!muted())
        world.run.finish(.failed(1))
        await waitFor { model.stage == .failed }

        world.antiDot = true
        #expect(model.checkMuting == .mac)
        await checkAgain()
        await check()
        #expect(muted())
        world.run.finish(.failed(1)) // it ends
        await waitFor { model.stage == .failed }
        #expect(!muted())

        await checkAgain()
        await check()
        #expect(muted())
        model.stopCheck()
        await waitFor { model.stage == .stopped }
        #expect(!muted())

        await checkAgain()
        await check()
        sut.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(!muted())
        world.run.finish(.stopped)
        await waitFor { model.stage == .stopped }

        await checkAgain()
        await check()
        #expect(muted())
        let (next, _) = makeSUT(scratch) // AutoHush crashed: the next launch
        next.putBackWhatWasLeft()
        #expect(!muted())
        world.run.finish(.stopped)
        await waitFor { model.stage == .stopped }
    }

    @MainActor
    @Test("the Mac's volume lowered for the music (Level the volume) is put back as AutoHush quits, and at the next launch after a crash")
    func loweredVolumePutBack() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        sut.volumeLeveler.lower(by: -6)
        #expect(scratch.volume.decibels == [0: -16])
        sut.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(scratch.volume.decibels == [0: -10])

        sut.volumeLeveler.lower(by: -6)
        let (next, _) = makeSUT(scratch) // AutoHush crashed: the next launch
        next.putBackWhatWasLeft()
        #expect(scratch.volume.decibels == [0: -10])
    }

    @MainActor
    @Test("Now Playing, shown in the menu bar for a press while the user hid it, is hidden again as AutoHush quits, and at the next launch after a crash, through the setting AutoHush is given")
    func nowPlayingPutBack() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        func shownForAPress() {
            scratch.nowPlaying.value = 16 // shown while active, for the press
            scratch.defaults.set(["value": 24, "pid": Int(getpid())], forKey: NowPlayingSetting.leftKey)
        }
        shownForAPress()
        sut.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(scratch.nowPlaying.value == 24 && scratch.defaults.object(forKey: NowPlayingSetting.leftKey) == nil)

        shownForAPress()
        let (next, _) = makeSUT(scratch) // AutoHush crashed: the next launch
        next.putBackWhatWasLeft()
        #expect(scratch.nowPlaying.value == 24 && scratch.defaults.object(forKey: NowPlayingSetting.leftKey) == nil)
    }

    // MARK: - Music player

    @MainActor
    @Test("with no player chosen, AutoHush waits for one and offers them all")
    func waitsForPlayer() {
        let (sut, _) = makeSUT(chosenPlayer: nil)
        #expect(sut.player == nil)
        #expect(sut.status.health == .needsPlayer("Choose a media player"))
        #expect(sut.status.statusLine == "Choose a media player")
        #expect(sut.status.playerOptions.map(\.name) == ["First", "Second"])
        #expect(sut.settingsModel.playerOptions == sut.status.playerOptions)
        #expect(sut.settingsModel.chosenPlayerID == nil)
    }

    @MainActor
    @Test("with no supported player installed, AutoHush asks for one, and none can be chosen until one is")
    func noPlayerInstalled() {
        let scratch = Scratch()
        scratch.installed = []
        let (sut, monitorings) = makeSUT(scratch, chosenPlayer: nil)
        #expect(sut.status.health == .needsPlayer("Choose a media player"))
        #expect(sut.status.playerOptions.allSatisfy { !$0.isInstalled })

        sut.chooseMusicPlayer(Players.first)
        #expect(sut.player == nil)
        #expect(scratch.preferences.musicPlayer == nil)
        #expect(monitorings.made.isEmpty)

        // Installed later: it can be chosen.
        scratch.installed = [Players.first]
        sut.refreshPlayerOptions()
        #expect(sut.status.health == .needsPlayer("Choose a media player"))
        sut.chooseMusicPlayer(Players.first)
        #expect(sut.player?.bundleID == Players.first)
    }

    @MainActor
    @Test("choosing a player stores it, shows it and starts over with it; choosing it again does nothing")
    func choosePlayer() async {
        let scratch = Scratch()
        let (sut, monitorings) = makeSUT(scratch, chosenPlayer: nil)

        sut.chooseMusicPlayer(Players.second)
        #expect(scratch.preferences.musicPlayer == Players.second)
        #expect(sut.status.playerName == "Second")
        #expect(!sut.settingsModel.playerCanFade) // its fade settings are dimmed
        #expect(sut.settingsModel.chosenPlayerName == "Second")
        #expect(sut.status.chosenPlayerID == Players.second)
        #expect(sut.settingsModel.chosenPlayerID == Players.second)
        #expect(sut.status.health == .starting)
        await waitFor { sut.status.health == .ready }
        #expect(monitorings.made.map(\.bundleID) == [Players.second])

        sut.chooseMusicPlayer(Players.second)
        await sut.session.waitUntilIdle()
        #expect(monitorings.made.count == 1)

        sut.chooseMusicPlayer(Players.first)
        #expect(sut.status.playerName == "First")
        #expect(sut.settingsModel.playerCanFade)
        await waitFor { monitorings.made.count == 2 }
        #expect(monitorings.made.map(\.bundleID) == [Players.second, Players.first])
    }

    /// A player only its sound tells about (`needsAudioLevels`), as an app
    /// added with Add an App can be.
    private struct HeardPlayer: MusicPlayer {
        static let id = "com.example.heard"
        let bundleID = Self.id
        let name = "Heard"
        let stateReportDelay: TimeInterval = 0
        var needsAudioLevels: Bool { true }
        func verifyControlAccess() async throws {}
        func playerState() async -> PlayerState { .playing }
        func pause() async throws {}
        func play() async throws {}
        func volume() async -> Int? { nil }
        func setVolume(_ volume: Int) async throws {}
        @MainActor
        func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
            MockStateObserver()
        }
    }

    @MainActor
    @Test("a player that isn't installed, isn't supported, or in AntiDot mode is told only by its sound, can't be chosen")
    func chooseUnavailablePlayer() {
        let scratch = Scratch()
        scratch.installed = [Players.first, HeardPlayer.id]
        scratch.players = MusicPlayerCatalog(players: [scratch.first, scratch.second, HeardPlayer()], formerDefault: Players.first)
        scratch.preferences.detectionMethod = .playbackSignals // AntiDot mode
        let (sut, monitorings) = makeSUT(scratch)

        sut.chooseMusicPlayer(Players.second)
        sut.chooseMusicPlayer("com.example.unknown")
        sut.chooseMusicPlayer(HeardPlayer.id)
        #expect(sut.player?.bundleID == Players.first)
        #expect(scratch.preferences.musicPlayer == Players.first)
        #expect(monitorings.made.isEmpty)
    }

    @MainActor
    @Test("another supported player opening shows it as installed, without starting over")
    func otherPlayerLaunch() async {
        let scratch = Scratch()
        scratch.installed = [Players.first]
        let (sut, monitorings) = makeSUT(scratch)
        await start(sut)

        scratch.installed.insert(Players.second)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.second)
        #expect(sut.status.playerOptions.map(\.isInstalled) == [true, true])
        await sut.session.waitUntilIdle()
        #expect(sut.status.health == .ready)
        #expect(monitorings.made.count == 1)
    }

    @MainActor
    @Test("while no player is chosen, a supported player opening brings the welcome window back")
    func playerLaunchWhileWaiting() {
        let (sut, monitorings) = makeSUT(chosenPlayer: nil)
        #expect(!sut.isShowingPlayerChooser)

        sut.handleApplicationDidLaunch(bundleIdentifier: Players.second)
        #expect(sut.isShowingPlayerChooser)
        #expect(monitorings.made.isEmpty)

        sut.chooseMusicPlayer(Players.second)
        // It goes on to what the player needs, and closes once done.
        #expect(sut.isShowingPlayerChooser)
        #expect(sut.settingsModel.welcomeAsksPermissions)
        sut.finishWelcome()
        #expect(!sut.isShowingPlayerChooser)
        #expect(!sut.settingsModel.welcomeAsksPermissions)
    }

    @MainActor
    @Test("opening the menu brings the welcome window forward while it's open, in case other windows covered it")
    func menuBringsWelcomeForward() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil)
        sut.menuWillOpen()
        #expect(scratch.chooser.broughtForward == 0) // not open

        sut.handleApplicationDidLaunch(bundleIdentifier: Players.second) // brings the welcome window
        sut.menuWillOpen()
        #expect(scratch.chooser.broughtForward == 1)

        scratch.chooser.close()
        sut.menuWillOpen()
        #expect(scratch.chooser.broughtForward == 1)
    }

    @MainActor
    @Test("the chosen player is left out of Settings → Sound Sources and the ignored apps")
    func chosenPlayerNotListedAsApp() {
        let scratch = Scratch()
        let first = AudioSource(id: Players.first, name: "First")
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
        scratch.preferences.recordSeen([first, vlc])
        scratch.preferences.ignoredApps = [first]
        let (sut, _) = makeSUT(scratch)
        #expect(sut.settingsModel.apps.map(\.id) == ["org.videolan.vlc"])
        #expect(sut.status.ignoredApps.isEmpty)

        // Once another player is chosen, it's an app like any other.
        sut.chooseMusicPlayer(Players.second)
        #expect(sut.settingsModel.apps.map(\.id) == [Players.first, "org.videolan.vlc"])
        #expect(sut.status.ignoredApps == [first])
    }

    @MainActor
    @Test("someone updating from before the choice keeps the former player, unasked")
    func updatingKeepsFormerPlayer() {
        let scratch = Scratch()
        scratch.preferences.lastLaunchedVersion = "0.3.11"
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil)
        #expect(sut.player?.bundleID == Players.first)
        #expect(sut.status.health == .starting)
    }

    @MainActor
    @Test("a stored player that is no longer supported is asked for again")
    func unknownStoredPlayer() {
        let (sut, _) = makeSUT(chosenPlayer: "com.example.gone")
        #expect(sut.player == nil)
        #expect(sut.status.health == .needsPlayer("Choose a media player"))
    }

    @MainActor
    @Test("Diagnostics in Settings follows what AutoHush sees: the apps with sound, found where Settings → Sound Sources lists them, and an added app's ways; while Settings is open, the window watch follows it on its page, launch at login, and the players while none is chosen")
    func diagnostics() async {
        let scratch = Scratch()
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        scratch.preferences.recordSeen([vlc])
        let (sut, monitorings) = makeSUT(scratch)
        #expect(sut.settingsModel.diagnostics == nil)
        await sut.refresh(.diagnostics)
        var diagnostics = sut.settingsModel.diagnostics
        #expect(diagnostics?.apps.isEmpty == true)
        #expect(diagnostics?.text.contains("Apps with Sound\nNo other app is playing sound right now.") == true)
        #expect(diagnostics?.sections.first?.rows.first?.value.hasPrefix("First") == true)
        #expect(diagnostics?.text.contains("Automation for First") == true)

        await start(sut)
        monitorings.made[0].audioReport = [ActiveAudioReport.Entry(id: vlc.id, name: "VLC", state: .playing)]
        await sut.refresh(.diagnostics)
        diagnostics = sut.settingsModel.diagnostics
        #expect(diagnostics?.apps.map(\.bundlePath) == [vlc.bundlePath])
        #expect(diagnostics?.text.contains("Apps with Sound\nVLC (org.videolan.vlc) — playing") == true)

        scratch.launchAtLogin.isEnabled = true // in System Settings
        await sut.refresh(.launchAtLogin)
        #expect(sut.settingsModel.launchAtLoginEnabled)
        #expect(AppDelegate.settingsNeeds(page: .general, hasPlayer: true) == [.notifications, .launchAtLogin, .permissions])
        #expect(AppDelegate.settingsNeeds(page: .diagnostics, hasPlayer: false)
                == [.notifications, .launchAtLogin, .permissions, .diagnostics, .players])

        // An app added with Add an App: the ways its check found.
        let added = Scratch()
        let setup = PlayerSetup(bundleID: "com.example.added", name: "Added", appURL: URL(fileURLWithPath: "/Applications/Added.app"),
                                ways: [.menu(menuName: "Controls")])
        let checked = CheckedPlayer(setup: setup, reports: nil)
        added.players = MusicPlayerCatalog(players: [added.first], found: { [checked] })
        added.installed.insert(setup.bundleID)
        let (withAdded, _) = makeSUT(added, chosenPlayer: setup.bundleID)
        withAdded.refreshDiagnostics()
        #expect(withAdded.settingsModel.diagnostics?.text.contains("Controlled by: \(AddAppText.wayTitle(.menu))") == true)
    }

    @MainActor
    @Test("only the chosen player is ever asked for permission to control it, and only once chosen")
    func onlyChosenPlayerIsAsked() async {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil)

        // Nothing is asked before a player is chosen, not even when one opens.
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first)
        await sut.session.waitUntilIdle()
        #expect(await scratch.first.verifyCallCount == 0)
        #expect(await scratch.second.verifyCallCount == 0)

        sut.chooseMusicPlayer(Players.second) // also closes the welcome window
        await TestWait.until { sut.status.health != .starting }
        #expect(sut.status.health == .ready)
        #expect(await scratch.second.verifyCallCount == 1)
        #expect(await scratch.first.verifyCallCount == 0)
    }

    @MainActor
    @Test("a chosen player that was uninstalled is reported as not installed")
    func chosenPlayerUninstalled() async {
        let scratch = Scratch()
        scratch.installed = []
        // The start stops at the install check, before scripting the player.
        let (sut, _) = makeSUT(scratch)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first)
        await TestWait.until { sut.status.health != .starting }
        #expect(sut.status.health == .degraded("First isn’t installed"))

        // Installed again: it's controlled afresh as soon as AutoHush notices.
        scratch.installed = [Players.first]
        sut.refreshPlayerOptions()
        await TestWait.until { sut.status.health == .ready }
        #expect(await scratch.first.verifyCallCount == 1)
    }

    @MainActor
    @Test("what the player session knows shows in the menu and Settings: why it can't control the player (its info button's alert too), the music, the apps playing and those that played, those playing as another player is chosen too; a pause held is no moment for an update's restart, and while Add an App's check runs it's held until the check ends")
    func sessionShown() async {
        let scratch = Scratch()
        await scratch.first.setFailVerify(MusicPlayerError.playerCommandFailed(.menuItemNotFound))
        let (sut, monitorings) = makeSUT(scratch)
        let alerts = CallLog()
        sut.runAlert = { alert in
            alerts.calls.append(([alert.messageText, alert.informativeText] + alert.buttons.map(\.title)).joined(separator: " | "))
            return .alertSecondButtonReturn // OK: System Settings stays closed
        }
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first)
        await TestWait.until { sut.status.health != .starting }
        #expect(sut.status.statusLine == "Can’t control First right now")
        #expect(sut.settingsModel.statusLine == "Can’t control First right now")
        #expect(sut.status.controlError?.text == "AutoHush can’t find Play/Pause in First’s menus.")
        // The info button after the card's line: what failed, then why, with OK only.
        sut.showControlError()
        #expect(alerts.calls.count == 1)
        #expect(alerts.calls.first?.hasPrefix("Can’t Control First | AutoHush can’t find Play/Pause in First’s menus.\n\n") == true)
        #expect(alerts.calls.first?.contains(ControlFailure.openMenuBarSettings) == false)
        // Now Playing hidden in the menu bar: it offers the pane that shows it.
        sut.status.controlError = ControlError(MusicPlayerError.playerCommandFailed(.nowPlayingHidden), player: "First")
        sut.showControlError()
        #expect(alerts.calls.last?.hasSuffix(" | \(ControlFailure.openMenuBarSettings) | OK") == true)

        await scratch.first.setFailVerify(nil)
        await TestWait.until { sut.status.health == .ready }
        #expect(sut.status.controlError == nil)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
        monitorings.made[0].send(.playback(.pausedByMonitor))
        monitorings.made[0].send(.activeSources([vlc]))
        #expect(sut.status.playback == .pausedByMonitor)
        #expect(sut.status.activeSources == [vlc])
        #expect(sut.settingsModel.apps.map(\.id) == [vlc.id]) // listed in Settings → Sound Sources as it plays
        #expect(!sut.isQuietMoment) // it holds a pause: no restart for an update now

        // Add an App's check runs: the pause stays until it ends.
        sut.holdsPlayerForCheck(true)
        sut.holdsPlayerForCheck(true) // again: nothing more
        #expect(sut.session.resumesHeld && monitorings.made[0].resumesHeld == [true])
        #expect(sut.status.statusLine == "Paused while a check runs")
        sut.holdsPlayerForCheck(false)
        #expect(!sut.session.resumesHeld && monitorings.made[0].resumesHeld == [true, false])
        #expect(!sut.status.playerHeldForCheck)

        // VLC stops: Recently Played lists it. Safari plays as another
        // player is chosen, which stops the monitoring: Safari too.
        monitorings.made[0].send(.activeSources([]))
        #expect(sut.status.recentSources() == [vlc])
        let safari = AudioSource(id: "com.apple.Safari", name: "Safari")
        monitorings.made[0].send(.activeSources([safari]))
        sut.chooseMusicPlayer(Players.second)
        #expect(sut.status.activeSources.isEmpty)
        #expect(sut.status.recentSources() == [safari, vlc])
    }

    @MainActor
    @Test("the chosen player uninstalled while AutoHush runs is noticed without a restart, and put back starts it again")
    func playerUninstalledWhileRunning() async {
        let scratch = Scratch()
        let (sut, monitorings) = makeSUT(scratch)
        await start(sut)
        monitorings.made[0].send(.playback(.musicPlaying))

        // Moved to the Trash: its folder changes, and nothing else happens.
        scratch.installed = []
        scratch.changeFolder()
        await TestWait.until { sut.status.health != .ready }
        #expect(sut.status.health == .degraded("First isn’t installed"))
        #expect(sut.status.playback == .unknown)
        #expect(monitorings.made[0].isStopped)

        // Put back: controlled afresh.
        scratch.installed = [Players.first]
        scratch.changeFolder()
        await TestWait.until { sut.status.health == .ready }
        #expect(monitorings.made.count == 2)
    }

    @MainActor
    @Test("opening the menu notices a player that was uninstalled while it wasn't running")
    func menuNoticesUninstalledPlayer() async {
        let scratch = Scratch()
        await scratch.first.setFailVerify(MusicPlayerError.playerNotRunning)
        let (sut, monitorings) = makeSUT(scratch)
        sut.session.launch()
        await waitFor { sut.status.health == .degraded("First isn’t running") }

        scratch.installed = []
        sut.refreshPlayerOptions() // what opening the menu or Settings does
        #expect(sut.status.health == .degraded("First isn’t installed"))
        #expect(sut.status.playerOptions.first { $0.bundleID == Players.first }?.isInstalled == false)

        // Asked again, it stays as it is.
        sut.refreshPlayerOptions()
        #expect(sut.status.health == .degraded("First isn’t installed"))
        // Only what listed the apps while it wasn't running, stopped now.
        #expect(monitorings.made.count == 1 && monitorings.made.allSatisfy(\.isStopped))
    }

    @MainActor
    @Test("the Applications folders are watched, and the one holding the chosen player's app")
    func watchesApplicationFolders() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let applicationFolders = Set(PlayerOption.applicationFolders.map(\.path))
        #expect(sut.watchedFolders == applicationFolders)

        sut.chooseMusicPlayer(Players.second) // in a folder inside /Applications
        #expect(sut.watchedFolders == applicationFolders.union(["/Applications/Players"]))

        // Gone: the Applications folders are enough to notice it coming back.
        scratch.installed = [Players.first]
        sut.refreshPlayerOptions()
        #expect(sut.watchedFolders == applicationFolders)
    }

    @MainActor
    @Test("with no player chosen, no folder is watched")
    func noWatchWithoutPlayer() {
        let (sut, _) = makeSUT(chosenPlayer: nil)
        sut.refreshPlayerOptions()
        #expect(sut.watchedFolders.isEmpty)
    }

    // MARK: - Permissions in the windows

    @MainActor
    @Test("a web app chosen in the welcome window is learned once the welcome window is done, or closed")
    func welcomeThenLearning() {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                        status: .learning(hasPlayed: false))
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed = [Players.first, webApp.bundleID]
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first) // brings the welcome window
        #expect(sut.isShowingPlayerChooser)

        sut.chooseMusicPlayer(webApp.bundleID)
        #expect(sut.settingsModel.welcomeAsksPermissions)
        #expect(!scratch.learningWindow.isOpen) // waits for the welcome window

        scratch.chooser.close() // closed instead of Done: the same
        sut.followWelcomeClosed()
        #expect(!sut.settingsModel.welcomeAsksPermissions)
        #expect(scratch.learningWindow.isOpen)
    }

    @MainActor
    @Test("the windows learn what's missing: the player's control permission, Audio Recording unless in AntiDot mode")
    func permissionsFollowed() async {
        let scratch = Scratch()
        scratch.automationStatus = OSStatus(errAEEventNotPermitted)
        scratch.audio = .denied
        let (sut, _) = makeSUT(scratch)
        await sut.refreshPermissions()
        #expect(sut.settingsModel.permissions.control == .automation(player: "First"))
        #expect(sut.settingsModel.permissions.controlAccess == .playerNotRunning)
        #expect(sut.settingsModel.permissions.audio == .denied)
        #expect(!sut.settingsModel.permissions.allSatisfied)

        scratch.running = [Players.first]
        await sut.refreshPermissions()
        #expect(sut.settingsModel.permissions.controlAccess == .denied)

        sut.settingsModel.useAntiDotMode()
        await sut.refreshPermissions()
        #expect(sut.settingsModel.permissions.audio == .notNeeded)
    }

    @MainActor
    @Test("a slow read of the permissions for the player chosen before, finishing after the new player's, doesn't replace the new one's")
    func stalePermissionsDropped() async {
        let scratch = Scratch()
        scratch.running = [Players.first] // its Automation is asked, and is slow
        let (sut, _) = makeSUT(scratch)
        scratch.automationGate.close()
        let slow = Task { await sut.refreshPermissions() }
        await waitFor { scratch.automationGate.waiting == 1 }
        sut.chooseMusicPlayer(Players.second)
        await sut.refreshPermissions()
        #expect(sut.settingsModel.permissions.control == .automation(player: "Second"))
        scratch.automationGate.open()
        await slow.value
        #expect(sut.settingsModel.permissions.control == .automation(player: "Second"))
    }

    @MainActor
    @Test("a missing permission's button opens the player, asks macOS, or opens System Settings, as it stands; only Audio Recording allowed there offers to reopen AutoHush")
    func permissionRequests() async {
        let scratch = Scratch()
        scratch.automationStatus = OSStatus(errAEEventNotPermitted)
        scratch.audio = .denied
        let (sut, _) = makeSUT(scratch)

        // Automation with the player closed: the button opens it.
        sut.requestPermission(.automation(player: "First"))
        await waitFor { !scratch.opened.isEmpty }
        #expect(scratch.opened.map(\.lastPathComponent) == ["\(Players.first).app"])

        // Automation turned down, the player running: System Settings, and no reopen is offered.
        scratch.running = [Players.first]
        sut.requestPermission(.automation(player: "First"))
        await waitFor { !scratch.asked.isEmpty }
        #expect(scratch.asked == ["open Privacy_Automation"])
        #expect(!sut.status.awaitsReopenForAudioRecording)

        // Accessibility (Add a Web App's Allow…): macOS's prompt, then System Settings.
        scratch.trusted = false
        sut.addWebAppModel.openAccessibilitySettings()
        await waitFor { scratch.asked.count == 3 }
        #expect(scratch.asked.suffix(2) == ["prompt accessibility", "open Privacy_Accessibility"])

        // Audio Recording turned down: System Settings, then AutoHush is to be reopened.
        sut.requestPermission(.systemAudioRecording)
        await waitFor { scratch.asked.count == 4 }
        #expect(scratch.asked.last == "open Privacy_AudioCapture")
        #expect(sut.status.awaitsReopenForAudioRecording)
        await sut.refreshPermissions()
        #expect(sut.settingsModel.permissions.audio == .needsReopen)

        // Never asked: macOS's own prompt.
        scratch.audio = .notDetermined
        sut.requestPermission(.systemAudioRecording)
        await waitFor { scratch.asked.count == 5 }
        #expect(scratch.asked.last == "ask audio")
    }

    // MARK: - The window watch

    @MainActor
    @Test("while the welcome window shows with no player chosen, the players installed and the permissions are followed; closed while it asked for them, it's done")
    func watchFollowsWelcome() async {
        let scratch = Scratch()
        scratch.installed = [Players.first]
        scratch.audio = .denied
        let clock = SteppedSleep()
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil, windowWatchSleep: clock.sleep)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first) // brings the welcome window
        await waitFor { clock.sleeping == 1 }
        #expect(sut.settingsModel.permissions.audio == .denied)

        scratch.installed.insert(Players.second) // installed meanwhile
        clock.step()
        await waitFor { sut.status.playerOptions.allSatisfy(\.isInstalled) }
        #expect(sut.status.playerOptions.allSatisfy { $0.isInstalled })

        sut.chooseMusicPlayer(Players.second) // it goes on to the permissions
        #expect(sut.settingsModel.welcomeAsksPermissions)
        // A player is chosen: the folder watch follows the players, the window watch no longer.
        await waitFor { clock.sleeping == 1 }
        scratch.installed.remove(Players.first)
        clock.step()
        await waitFor { clock.sleeping == 1 }
        #expect(sut.status.playerOptions.first { $0.bundleID == Players.first }?.isInstalled == true)
        scratch.chooser.close() // closed instead of Done: the same
        clock.step()
        await waitFor { !sut.settingsModel.welcomeAsksPermissions }
        #expect(!sut.settingsModel.welcomeAsksPermissions)
    }

    @MainActor
    @Test("while Settings is open, the window watch follows what its page needs: launch at login, switched on in System Settings")
    func watchFollowsSettings() async {
        let scratch = Scratch()
        let clock = SteppedSleep()
        let (sut, _) = makeSUT(scratch, windowWatchSleep: clock.sleep)
        sut.settingsWindowController = SettingsWindowController(model: sut.settingsModel)
        sut.settingsWindowController?.show(page: .general)
        defer { sut.settingsWindowController?.close() }
        sut.windowWatch.wake()
        await waitFor { clock.sleeping == 1 }
        #expect(!sut.settingsModel.launchAtLoginEnabled)
        scratch.launchAtLogin.isEnabled = true
        clock.step()
        await waitFor { sut.settingsModel.launchAtLoginEnabled }
        #expect(sut.settingsModel.launchAtLoginEnabled)
    }

    @MainActor
    @Test("while only the learning window shows, the permissions are followed, not the players")
    func watchFollowsLearning() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                        status: .learning(hasPlayed: false))
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let clock = SteppedSleep()
        let (sut, _) = makeSUT(scratch, windowWatchSleep: clock.sleep)
        sut.chooseMusicPlayer(webApp.bundleID) // opens the learning window
        #expect(scratch.learningWindow.isOpen)
        await waitFor { clock.sleeping == 1 }

        scratch.audio = .denied
        scratch.installed.remove(Players.first)
        clock.step()
        await waitFor { sut.settingsModel.permissions.audio == .denied }
        #expect(sut.settingsModel.permissions.audio == .denied)
        #expect(sut.status.playerOptions.first { $0.bundleID == Players.first }?.isInstalled == true) // not looked at again
    }

    // MARK: - Permissions while running

    @MainActor
    @Test("reopening opens AutoHush again once it has quit, then quits; if that can't be set up, it stays open")
    func reopenRelaunchesThenQuits() {
        let (sut, _) = makeSUT()
        var calls: [String] = []
        sut.reopen(openAfterExit: { calls.append("open \($0.lastPathComponent)") }, terminate: { calls.append("quit") })
        #expect(calls == ["open \(Bundle.main.bundleURL.lastPathComponent)", "quit"])

        calls = []
        sut.reopen(openAfterExit: { _ in throw CocoaError(.fileNoSuchFile) }, terminate: { calls.append("quit") })
        #expect(calls.isEmpty)
    }

    // MARK: - The menu

    @MainActor
    @Test("the menu shows the app's status, and its items reach AutoHush's own settings, player session, choice of player and the player itself; while it's open, an update doesn't restart AutoHush")
    func menuWiring() async throws {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        sut.showStatusMenu()
        let menu = try #require(sut.statusMenu)
        defer { menu.remove() }
        await start(sut)
        #expect(menu.status == sut.status)

        menu.perform(.toggleAutoPause)
        #expect(!sut.userSettings.state.autoPauseActive)
        #expect(sut.status.autoPause == .off && menu.status.autoPause == .off)

        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
        menu.perform(.setIgnored(vlc, true))
        #expect(sut.session.settings.ignored == [vlc.id])
        #expect(menu.status.ignoredApps == [vlc])

        // A player chosen from its list is AppDelegate's to choose.
        await scratch.second.setFailVerify(MusicPlayerError.playerNotResponding)
        // Its own notification centers: no other test's window becoming key closes it.
        menu.notificationCenter = NotificationCenter()
        menu.workspaceCenter = NotificationCenter()
        menu.open(showsPanel: false)
        #expect(!sut.isQuietMoment) // the menu is open
        menu.perform(.openSide(.players))
        #expect(menu.model.players.supportedApps.contains { $0.id == Players.second })
        menu.perform(.choosePlayer(Players.second)) // chosen in place: the menu stays open
        await TestWait.until { sut.player?.bundleID == Players.second }
        #expect(sut.player?.bundleID == Players.second)
        #expect(menu.status.chosenPlayerID == Players.second)
        #expect(menu.isMenuOpen && !menu.model.isChoosingPlayer)
        menu.close()

        // Its start failed: Retry is the player session's.
        await TestWait.until { sut.status.canRetry }
        menu.perform(.retry)
        #expect(sut.status.health == .starting && menu.status.health == .starting)

        // The card's chips: Unmute plays the player, Reopen reopens it.
        menu.perform(.unmutePlayer)
        await TestWait.until { await scratch.second.playCallCount == 1 }
        #expect(await scratch.second.playCallCount == 1)
        menu.perform(.reopenPlayer)
        await TestWait.until { await scratch.second.reopenCount == 1 }
        #expect(await scratch.second.reopenCount == 1)
    }

    // MARK: - Settings and updates

    @MainActor
    @Test("the user's settings show in the menu and Settings, and reach the monitoring")
    func userSettingsShown() async {
        let scratch = Scratch()
        let (sut, monitorings) = makeSUT(scratch)
        await start(sut)
        let monitoring = monitorings.made[0]
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")

        sut.userSettings.snooze(.oneHour)
        guard case .snoozed = sut.status.autoPause else {
            Issue.record("expected snoozed, got \(sut.status.autoPause)")
            return
        }
        #expect(!sut.settingsModel.isAutoPauseOn)
        #expect(sut.settingsModel.autoPauseNote?.hasPrefix("Turned off until") == true)
        #expect(monitoring.autoPause == false)
        sut.userSettings.setAutoPause(true)
        #expect(sut.settingsModel.isAutoPauseOn && sut.settingsModel.autoPauseNote == nil)
        #expect(monitoring.autoPause == true)

        sut.userSettings.setIgnored(vlc, true)
        #expect(sut.status.ignoredApps == [AudioSource(id: vlc.id, name: "VLC")])
        #expect(sut.settingsModel.apps.map(\.id) == [vlc.id])
        #expect(sut.settingsModel.apps.first?.isIgnored == true)
        #expect(monitoring.ignored == [vlc.id])

        sut.userSettings.setTimings(TimingSettings(stopGrace: 4))
        #expect(sut.settingsModel.timings.stopGrace == 4)
        #expect(monitoring.configurations.last?.sourceStopGrace == 4)
        sut.userSettings.setDetectionMethod(.playbackSignals)
        #expect(sut.settingsModel.detectionMethod == .playbackSignals)
        #expect(monitoring.detectionMethods == [.playbackSignals])
    }

    @MainActor
    @Test("with nothing monitored, quitting doesn't wait; while a player is, the quit goes on once its volume is back, once only; a stop that never ends lets it go on after the wait")
    func quitting() async {
        let (idle, _) = makeSUT()
        #expect(idle.applicationShouldTerminate(NSApplication.shared) == .terminateNow)

        let (sut, monitorings) = makeSUT()
        await start(sut)
        let replies = CallLog()
        #expect(sut.shouldTerminate(wait: 60) { replies.calls.append("after \(monitorings.made[0].restoredStops) stop") }
                == .terminateLater)
        await sut.quitting?.value
        #expect(replies.calls == ["after 1 stop"]) // the volume back first

        // An added app that doesn't let go of what it turned on in its app.
        let scratch = Scratch()
        let added = AddedPlayer(bundleID: "com.example.added", name: "Added")
        await added.holdReleases()
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [added] })
        scratch.installed.insert(added.bundleID)
        let (stuck, _) = makeSUT(scratch, chosenPlayer: added.bundleID)
        let stuckReplies = CallLog()
        #expect(stuck.shouldTerminate(wait: 0.05) { stuckReplies.calls.append("reply") } == .terminateLater)
        await TestWait.until { stuckReplies.calls.count == 1 } // after the wait
        #expect(stuckReplies.calls.count == 1)
        #expect(await added.releases == 0)
        await added.letGo()
        await stuck.quitting?.value
        #expect(stuckReplies.calls.count == 1) // not twice
        #expect(await added.releases == 1)
    }

    @MainActor
    @Test("a newer release found by an update check is offered in the menu and Settings")
    func updateAvailable() async {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch, updateChecker: .latestRelease("v0.3.0"))
        #expect(sut.settingsModel.currentVersion == "0.2.0")
        #expect(sut.settingsModel.lastUpdateCheck == nil)
        await sut.updates.check(userInitiated: false)
        #expect(sut.status.updateOffer == UpdateOffer(release: sut.updates.availableUpdate!, state: .available))
        #expect(sut.settingsModel.updateStatus == "Version 0.3.0 is available.")
        #expect(sut.settingsModel.updateTitle == "Version 0.3.0 is available.")
        #expect(sut.settingsModel.lastUpdateCheck == scratch.preferences.lastUpdateCheck)
        #expect(sut.settingsModel.lastUpdateCheck != nil)
    }

    @MainActor
    @Test("the update settings show in Settings as they're changed; the choice starts at installing")
    func updateSettingsShown() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        #expect(sut.settingsModel.automaticUpdates == .install)
        #expect(sut.settingsModel.updateInstallNote == nil)
        sut.updates.setMode(.download)
        #expect(sut.settingsModel.automaticUpdates == .download)
        sut.updates.setChecksAutomatically(false)
        #expect(!sut.settingsModel.checksForUpdatesAutomatically)
    }

    @MainActor
    @Test("Settings says why AutoHush can't update itself")
    func installUnavailableNote() {
        let (sut, _) = makeSUT(updateInstaller: MockUpdateInstaller(unavailability: .readOnlyLocation))
        #expect(sut.settingsModel.updateInstallNote == "AutoHush can’t update itself, because it can’t write to the folder it’s in.")
    }
}

/// An app macOS says opened, as the launch notice carries it.
private final class FakeRunningApplication: NSRunningApplication, @unchecked Sendable {
    private let fakeBundleID: String
    private let fakeBundleURL: URL?
    init(bundleID: String, bundleURL: URL? = nil) {
        fakeBundleID = bundleID
        fakeBundleURL = bundleURL
        super.init()
    }
    override var bundleIdentifier: String? { fakeBundleID }
    override var bundleURL: URL? { fakeBundleURL }
}

/// An app added with Add an App, as a check's setup makes one: what it
/// turned on in its app to be controlled (a mute, a switch) is counted as
/// it goes back off. Held, a release waits for `letGo()`.
private actor AddedPlayer: MusicPlayer {
    nonisolated let bundleID: String
    nonisolated let name: String
    private let needsReopening: Bool
    private let inner: MockMusicPlayer
    private(set) var releases = 0
    private var heldReleases: [CheckedContinuation<Void, Never>]?

    init(bundleID: String, name: String, needsReopening: Bool = false) {
        self.bundleID = bundleID
        self.name = name
        self.needsReopening = needsReopening
        inner = MockMusicPlayer(bundleID: bundleID, name: name)
    }

    nonisolated var kind: MusicPlayerKind { .checkedApp }
    nonisolated var releasesOnQuit: Bool { true }
    nonisolated var stateReportDelay: TimeInterval { 0 }
    nonisolated var canFade: Bool { false }

    func verifyControlAccess() async throws {}
    func playerState() async -> PlayerState { await inner.playerState() }
    func pause() async throws { try await inner.pause() }
    func play() async throws { try await inner.play() }
    func volume() async -> Int? { nil }
    func setVolume(_ volume: Int) async throws {}
    func needsReopen() async -> Bool { needsReopening }
    @MainActor
    func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        MockStateObserver()
    }

    func holdReleases() { heldReleases = heldReleases ?? [] }

    func letGo() {
        heldReleases?.forEach { $0.resume() }
        heldReleases = nil
    }

    func release() async {
        if heldReleases != nil { await withCheckedContinuation { heldReleases?.append($0) } }
        releases += 1
    }
}

/// The setups of the apps added with Add an App, kept in memory as the
/// preferences keep them: by bundle ID, read by name.
private final class SetupsInMemory: PlayerSetupStore, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [String: PlayerSetup] = [:]
    func setups() -> [PlayerSetup] { lock.withLock { kept.values.sorted { $0.name < $1.name } } }
    func save(_ setup: PlayerSetup) { lock.withLock { kept[setup.bundleID] = setup } }
    func forget(_ bundleID: String) { lock.withLock { kept[bundleID] = nil } }
}

/// The apps added with Add an App, as the catalog finds them: a stand-in for
/// each setup kept, made again when its setup changes (checked again), as
/// `CheckedPlayers` makes them.
private final class AddedApps: @unchecked Sendable {
    private let setups: SetupsInMemory
    private let needReopening: Bool
    private let lock = NSLock()
    private var made: [String: (setup: PlayerSetup, player: AddedPlayer)] = [:]

    init(_ setups: SetupsInMemory, needReopening: Bool = false) {
        self.setups = setups
        self.needReopening = needReopening
    }

    func players() -> [any MusicPlayer] {
        let kept = setups.setups()
        return lock.withLock {
            kept.map { setup in
                if let known = made[setup.bundleID], known.setup == setup { return known.player }
                let player = AddedPlayer(bundleID: setup.bundleID, name: setup.name, needsReopening: needReopening)
                made[setup.bundleID] = (setup, player)
                return player
            }
        }
    }

    /// The one made last for `bundleID`.
    func player(_ bundleID: String) -> AddedPlayer? { lock.withLock { made[bundleID]?.player } }
}

/// Holds the Automation queries that reach it while closed, until it opens.
private final class AutomationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isClosed = false
    private var held: [CheckedContinuation<Void, Never>] = []
    var waiting: Int { lock.withLock { held.count } }

    func close() { lock.withLock { isClosed = true } }

    func open() {
        let released = lock.withLock {
            isClosed = false
            defer { held = [] }
            return held
        }
        released.forEach { $0.resume() }
    }

    func pass() async {
        await withCheckedContinuation { continuation in
            let passes = lock.withLock {
                if isClosed { held.append(continuation) }
                return !isClosed
            }
            if passes { continuation.resume() }
        }
    }
}

/// The menu bar's Now Playing setting, in memory.
private final class NowPlayingInMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int? = 24 // hidden by the user
    var value: Int? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }

    var setting: NowPlayingSetting.Setting {
        NowPlayingSetting.Setting(read: { self.value }, write: { self.value = $0 })
    }
}

/// Players found on the Mac, changed by a test.
private final class FoundPlayers: @unchecked Sendable {
    private let lock = NSLock()
    private var _players: [any MusicPlayer] = []
    var players: [any MusicPlayer] {
        get { lock.withLock { _players } }
        set { lock.withLock { _players = newValue } }
    }
}
