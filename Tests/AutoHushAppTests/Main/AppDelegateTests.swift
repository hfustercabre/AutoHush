import AppKit
import Foundation
import os
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("AppDelegate")
struct AppDelegateTests {
    /// Counts bootstrap requests; the real bootstrap would script the music
    /// player and tap real audio processes from inside the test process.
    @MainActor
    private final class BootstrapCounter {
        var count = 0
    }

    /// In-memory preferences and a downloads folder of its own, so tests
    /// never write preference files or touch AutoHush's real Caches. Two
    /// stand-in music players to choose from, which of them are installed
    /// (the second in a folder inside /Applications), and folder watches the
    /// test fires.
    @MainActor
    private final class Scratch {
        var preferences = Preferences(store: InMemoryPreferenceStore())
        let downloads = FileManager.default.temporaryDirectory.appending(path: "AppDelegateTests-\(UUID().uuidString)")
        let notifier = MockUpdateNotifier()
        let first = MockMusicPlayer(bundleID: Players.first, name: "First", failVerifyWith: Denied.automation)
        let second = MockMusicPlayer(bundleID: Players.second, name: "Second", canFade: false, failVerifyWith: Denied.automation)
        lazy var players = MusicPlayerCatalog(players: [first, second], formerDefault: Players.first)
        var installed: Set<String> = [Players.first, Players.second]
        let chooser = FakePlayerChooser()
        let learningWindow = FakeLearningWindow()
        let addWindow = FakeAddWebAppWindow()
        var maker = FakeWebAppMaker(.failure(.notAWebAddress))
        var opened: [URL] = []
        /// The permissions as the stand-in system reports them, and what was asked of it.
        var trusted = true
        var automationStatus: OSStatus = noErr
        var running: Set<String> = []
        var audio: AudioCapturePermission? = .granted
        var asked: [String] = []
        lazy var permissionCenter = PermissionCenter(system: .init(
            isTrusted: { [unowned self] in self.trusted },
            promptAccessibility: { [unowned self] in self.asked.append("prompt accessibility") },
            automation: { [status = automationStatus] _, ask in ask ? noErr : status },
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

        func watch(_ folder: URL, onChange: @escaping @MainActor () -> Void) -> AnyObject? {
            onFolderChange = onChange
            return NSObject()
        }

        func changeFolder() {
            onFolderChange?()
        }

        deinit {
            try? FileManager.default.removeItem(at: downloads)
        }
    }

    /// Every stand-in player refuses control, so a real bootstrap stops at
    /// the permission check, before it would monitor anything.
    private enum Denied {
        static let automation = MusicPlayerError.automationPermissionDenied
    }

    private enum Players {
        static let first = "com.example.first"
        static let second = "com.example.second"
    }

    /// `chosenPlayer`: the player already chosen before this launch, if any.
    /// `realBootstrap`: only for a bootstrap that stops before the player is
    /// scripted.
    @MainActor
    private func makeSUT(
        _ scratch: Scratch = Scratch(),
        chosenPlayer: String? = Players.first,
        realBootstrap: Bool = false,
        updateChecker: UpdateChecker = UpdateChecker { _ in throw URLError(.notConnectedToInternet) },
        updateInstaller: MockUpdateInstaller = MockUpdateInstaller(),
        learningPauseWait: Duration = .seconds(60)
    ) -> (AppDelegate, BootstrapCounter) {
        if let chosenPlayer { scratch.preferences.musicPlayer = chosenPlayer }
        let counter = BootstrapCounter()
        let countBootstrap: @MainActor () -> Void = { counter.count += 1 }
        let sut = AppDelegate(
            preferences: scratch.preferences,
            launchAtLoginController: MockLaunchAtLoginController(isEnabled: false),
            updateChecker: updateChecker,
            updateInstaller: updateInstaller,
            updateNotifier: scratch.notifier,
            updateDownloadsFolder: scratch.downloads,
            players: scratch.players,
            locateApp: { scratch.locate($0) },
            makePlayerChooser: { _ in scratch.chooser },
            makeLearningWindow: { _ in scratch.learningWindow },
            webAppMaker: scratch.maker,
            makeAddWebAppWindow: { _, _ in scratch.addWindow },
            openApp: { scratch.opened.append($0) },
            learnedWindowDelay: .zero,
            learningPauseWait: learningPauseWait,
            currentVersion: AppVersion("0.2.0"),
            permissionRetryInterval: 0.05,
            retryDelays: 0.02...0.08,
            watchFolder: { scratch.watch($0, onChange: $1) },
            installCheckDelay: .zero,
            permissionCenter: scratch.permissionCenter,
            bootstrapOverride: realBootstrap ? nil : countBootstrap
        )
        return (sut, counter)
    }

    // MARK: - Players that learn

    @MainActor
    private func waitFor(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @MainActor
    @Test("choosing a web app AutoHush must learn asks for it in a window, shows the steps, and closes it once learned")
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
        #expect(scratch.learningWindow.isVisible)
        #expect(sut.status.learningHasPlayed == false)
        #expect(sut.settingsModel.learningHasPlayed == false)

        webApp.set(.learning(hasPlayed: true))
        await waitFor { sut.status.learningHasPlayed == true }
        #expect(sut.settingsModel.learningHasPlayed == true)

        webApp.set(.learned)
        await waitFor { !scratch.learningWindow.isVisible }
        #expect(!scratch.learningWindow.isVisible)
        #expect(sut.status.learning == .learned)
        #expect(sut.status.learningHasPlayed == nil)

        sut.chooseMusicPlayer(Players.first)
        #expect(sut.status.learning == nil)
        sut.chooseMusicPlayer(webApp.bundleID) // learned already: no window
        #expect(scratch.learningWindow.shownCount == 1)
    }

    @MainActor
    @Test("a web app's learned controls can be learned again: the player forgets them and the learning window opens")
    func learnControlsAgain() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music", status: .learned)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch)
        sut.chooseMusicPlayer(webApp.bundleID)
        await waitFor { sut.status.learning == .learned }
        #expect(!scratch.learningWindow.isVisible)
        #expect(sut.status.canLearnControlsAgain)
        #expect(sut.settingsModel.canLearnControlsAgain)

        sut.learnControlsAgain()
        await waitFor { scratch.learningWindow.isVisible && sut.status.learningHasPlayed != nil }
        #expect(scratch.learningWindow.isVisible)
        #expect(webApp.learnAgainCount == 1)
        #expect(sut.status.learningHasPlayed == false)
        #expect(!sut.status.canLearnControlsAgain) // until they're learned
        #expect(!sut.settingsModel.canLearnControlsAgain)

        sut.learnControlsAgain() // learning already: nothing to forget
        try? await Task.sleep(for: .milliseconds(50))
        #expect(webApp.learnAgainCount == 1)

        sut.chooseMusicPlayer(Players.first) // a player that learns nothing
        #expect(!sut.status.canLearnControlsAgain)
        #expect(!sut.settingsModel.canLearnControlsAgain)
    }

    @MainActor
    @Test("while a permission is missing, the learning window asks for it first; the menu and Settings show no steps")
    func learningWaitsForPermission() {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                        status: .learning(hasPlayed: false))
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch)

        sut.chooseMusicPlayer(webApp.bundleID)
        sut.setHealth(.needsPermission(.accessibility(player: "YT Music")))
        #expect(scratch.learningWindow.isVisible) // with the permission as its first step
        #expect(sut.settingsModel.playerNeedsPermission)
        #expect(sut.status.learningHasPlayed == nil) // the menu asks for the permission instead
        #expect(sut.settingsModel.learningHasPlayed == nil)

        sut.setHealth(.ready) // allowed: the retry started monitoring
        #expect(!sut.settingsModel.playerNeedsPermission)
        #expect(sut.status.learningHasPlayed == false)
        #expect(sut.settingsModel.learningHasPlayed == false)
        #expect(scratch.learningWindow.shownCount == 1)
    }

    @MainActor
    @Test("a web app that isn't running yet still opens the learning window, which says to play it")
    func learningWindowForPlayerNotRunning() {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                        status: .learning(hasPlayed: false))
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch)

        sut.chooseMusicPlayer(webApp.bundleID)
        sut.setHealth(.degraded("YT Music is not running"))
        #expect(scratch.learningWindow.isVisible)
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
        #expect(scratch.addWindow.isVisible)
        sut.addWebAppModel.address = "play.qobuz.com"
        sut.addWebAppModel.continueTapped()
        await waitFor { sut.addWebAppModel.phase == .readyToAdd(site: "play.qobuz.com") }
        #expect(found.players.isEmpty) // nothing's added before the user clicks Add to Dock
        sut.addWebAppModel.addTapped()
        await waitFor { sut.status.chosenPlayerID == webApp.bundleID && !scratch.opened.isEmpty }
        #expect(sut.status.chosenPlayerID == webApp.bundleID)
        #expect(sut.addWebAppModel.phase == .learning(name: "Qobuz", alreadyThere: false))
        #expect(scratch.opened == [appURL])
        #expect(!scratch.learningWindow.isVisible) // the add window shows the steps

        webApp.set(.learned)
        await waitFor { !scratch.addWindow.isVisible }
        #expect(!scratch.addWindow.isVisible)
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
        await waitFor { sut.status.chosenPlayerID == webApp.bundleID && !scratch.addWindow.isVisible }
        #expect(!scratch.addWindow.isVisible) // one window asks: the welcome window
        #expect(sut.isShowingPlayerChooser)
        #expect(sut.settingsModel.welcomeAsksPermissions)
        #expect(!scratch.learningWindow.isVisible)

        sut.finishWelcome()
        #expect(scratch.learningWindow.isVisible)
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
        #expect(scratch.addWindow.isVisible)
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
        sut.addWebAppModel.windowClosed()
        #expect(sut.addWebAppModel.phase == .entering)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!made.withLock { $0 })
        #expect(scratch.opened.isEmpty)
    }

    @MainActor
    @Test("It's Playing and It's Paused go to the player; a click it can't take says why under its step")
    func learningClicks() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                        status: .learning(hasPlayed: false))
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch)
        sut.chooseMusicPlayer(webApp.bundleID)

        webApp.answer(playing: .notHeard)
        sut.learningStep(.itsPlaying)
        await waitFor { sut.status.learningNote == .notHeard }
        #expect(sut.settingsModel.learningNote == .notHeard)
        #expect(sut.status.learningPauseDeadline == nil)

        webApp.answer(playing: .noted, paused: .nothingChanged)
        sut.learningStep(.itsPlaying)
        await waitFor { sut.status.learningHasPlayed == true }
        #expect(sut.status.learningNote == nil)
        let deadline = sut.status.learningPauseDeadline
        #expect(deadline.map { abs($0.timeIntervalSinceNow - 60) < 2 } == true)
        #expect(sut.settingsModel.learningPauseDeadline == deadline)

        sut.learningStep(.itsPaused)
        await waitFor { sut.status.learningNote == .nothingChanged }
        #expect(sut.status.learningPauseDeadline == deadline) // the minute goes on

        // The page went before It's Paused: back to the first step, saying why.
        webApp.answer(paused: .cantSeePage)
        sut.learningStep(.itsPaused)
        await waitFor { sut.status.learningHasPlayed == false && sut.status.learningNote == .cantSeePage }
        #expect(sut.status.learningNote == .cantSeePage)
        #expect(sut.status.learningPauseDeadline == nil)

        webApp.answer(playing: .noted, paused: .noted)
        sut.learningStep(.itsPlaying)
        await waitFor { sut.status.learningHasPlayed == true }
        sut.learningStep(.itsPaused)
        await waitFor { sut.status.learning == .learned }
        #expect(sut.status.learningNote == nil)
        #expect(sut.status.learningPauseDeadline == nil)
    }

    @MainActor
    @Test("It's Paused as the minute ends: learned, and nothing says the minute went by")
    func learningPausedAtTheLastMoment() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                        status: .learning(hasPlayed: false))
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch, learningPauseWait: .milliseconds(50))
        sut.chooseMusicPlayer(webApp.bundleID)
        webApp.learnAtTheLastMoment()
        sut.learningStep(.itsPlaying)
        await waitFor { sut.status.learning == .learned }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(webApp.restartCount == 0)
        #expect(sut.status.learningNote == nil)
    }

    @MainActor
    @Test("without It's Paused in time, learning starts over and says why")
    func learningPauseTimesOut() async {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                        status: .learning(hasPlayed: false))
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch, learningPauseWait: .milliseconds(50))
        sut.chooseMusicPlayer(webApp.bundleID)
        sut.learningStep(.itsPlaying)
        await waitFor { sut.status.learningHasPlayed == true }
        await waitFor { sut.status.learningHasPlayed == false }
        #expect(webApp.restartCount == 1)
        #expect(sut.status.learningNote == .timedOut)
        #expect(sut.status.learningPauseDeadline == nil)
        #expect(scratch.learningWindow.isVisible) // still learning

        // Choosing another player forgets it all.
        sut.chooseMusicPlayer(Players.first)
        #expect(sut.status.learningNote == nil)
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
        await waitFor { !scratch.addWindow.isVisible }
        #expect(!scratch.addWindow.isVisible)
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
    @Test("a chosen web app that's deleted is no longer chosen: no learning card, and the status line asks for a player")
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
        #expect(sut.status.learningHasPlayed == false)

        found.players = [] // moved to the Trash, or deleted
        scratch.changeFolder()
        await waitFor { sut.status.chosenPlayerID == nil }
        #expect(sut.status.chosenPlayerID == nil)
        #expect(sut.status.learningHasPlayed == nil)
        #expect(sut.settingsModel.learningHasPlayed == nil)
        #expect(scratch.preferences.musicPlayer == nil)
        #expect(sut.status.health == .waitingForPlayer(among: sut.status.playerOptions))
    }

    @MainActor
    @Test("a web app chosen earlier shows its steps at launch, without the window")
    func learningAtLaunch() {
        let scratch = Scratch()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music",
                                        status: .learning(hasPlayed: false))
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [webApp] })
        scratch.installed.insert(webApp.bundleID)
        let (sut, _) = makeSUT(scratch, chosenPlayer: webApp.bundleID)
        #expect(sut.status.learningHasPlayed == false)
        #expect(!scratch.learningWindow.isVisible)
    }

    @MainActor
    @Test("another app's launch does not change health state or re-bootstrap")
    func otherAppLaunchDoesNothing() {
        let (sut, bootstraps) = makeSUT()

        #expect(sut.status.health == .starting)
        sut.handleApplicationDidLaunch(bundleIdentifier: "org.videolan.vlc")
        #expect(sut.status.health == .starting)
        #expect(bootstraps.count == 0)
    }

    @MainActor
    @Test("the chosen player's launch sets app back to starting and re-bootstraps")
    func playerLaunchSetsStartingState() {
        let (sut, bootstraps) = makeSUT()
        sut.setHealth(.degraded("First is not running"))

        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first)

        #expect(sut.status.health == .starting)
        #expect(bootstraps.count == 1)
    }

    @MainActor
    @Test("nil bundle identifier does nothing")
    func nilBundleIdentifierDoesNothing() {
        let (sut, bootstraps) = makeSUT()
        sut.setHealth(.ready)

        sut.handleApplicationDidLaunch(bundleIdentifier: nil)

        #expect(sut.status.health == .ready)
        #expect(bootstraps.count == 0)
    }

    // MARK: - Music player

    @MainActor
    @Test("with no player chosen, AutoHush waits for one and offers them all")
    func waitsForPlayer() {
        let (sut, _) = makeSUT(chosenPlayer: nil)
        #expect(sut.player == nil)
        #expect(sut.status.health == .needsPlayer("Choose a music player"))
        #expect(sut.status.statusLine == "Choose a music player")
        #expect(sut.status.playerOptions.map(\.name) == ["First", "Second"])
        #expect(sut.settingsModel.playerOptions == sut.status.playerOptions)
        #expect(sut.settingsModel.chosenPlayerID == nil)
        #expect(sut.currentConfiguration.musicPlayerBundleID == nil)
    }

    @MainActor
    @Test("with no supported player installed, AutoHush says so, and none can be chosen")
    func noPlayerInstalled() {
        let scratch = Scratch()
        scratch.installed = []
        let (sut, bootstraps) = makeSUT(scratch, chosenPlayer: nil)
        #expect(sut.status.health == .needsPlayer("No supported music player is installed"))
        #expect(sut.status.playerOptions.allSatisfy { !$0.isInstalled })

        sut.chooseMusicPlayer(Players.first)
        #expect(sut.player == nil)
        #expect(scratch.preferences.musicPlayer == nil)
        #expect(bootstraps.count == 0)

        // Installed later: it can be chosen.
        scratch.installed = [Players.first]
        sut.refreshPlayerOptions()
        #expect(sut.status.health == .needsPlayer("Choose a music player"))
        sut.chooseMusicPlayer(Players.first)
        #expect(sut.player?.bundleID == Players.first)
    }

    @MainActor
    @Test("choosing a player stores it, shows it and starts over with it; choosing it again does nothing")
    func choosePlayer() {
        let scratch = Scratch()
        let (sut, bootstraps) = makeSUT(scratch, chosenPlayer: nil)

        sut.chooseMusicPlayer(Players.second)
        #expect(scratch.preferences.musicPlayer == Players.second)
        #expect(sut.status.playerName == "Second")
        #expect(!sut.settingsModel.playerCanFade) // its fade settings are dimmed
        #expect(sut.settingsModel.chosenPlayerName == "Second")
        #expect(sut.status.chosenPlayerID == Players.second)
        #expect(sut.settingsModel.chosenPlayerID == Players.second)
        #expect(sut.status.health == .starting)
        #expect(sut.currentConfiguration.musicPlayerBundleID == Players.second)
        #expect(bootstraps.count == 1)

        sut.chooseMusicPlayer(Players.second)
        #expect(bootstraps.count == 1)

        sut.chooseMusicPlayer(Players.first)
        #expect(sut.status.playerName == "First")
        #expect(sut.settingsModel.playerCanFade)
        #expect(sut.currentConfiguration.musicPlayerBundleID == Players.first)
        #expect(bootstraps.count == 2)
    }

    @MainActor
    @Test("a player that isn't installed, or isn't supported, can't be chosen")
    func chooseUnavailablePlayer() {
        let scratch = Scratch()
        scratch.installed = [Players.first]
        let (sut, bootstraps) = makeSUT(scratch)

        sut.chooseMusicPlayer(Players.second)
        sut.chooseMusicPlayer("com.example.unknown")
        #expect(sut.player?.bundleID == Players.first)
        #expect(scratch.preferences.musicPlayer == Players.first)
        #expect(bootstraps.count == 0)
    }

    @MainActor
    @Test("another supported player opening shows it as installed, without starting over")
    func otherPlayerLaunch() {
        let scratch = Scratch()
        scratch.installed = [Players.first]
        let (sut, bootstraps) = makeSUT(scratch)
        sut.setHealth(.ready)

        scratch.installed.insert(Players.second)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.second)
        #expect(sut.status.playerOptions.map(\.isInstalled) == [true, true])
        #expect(sut.status.health == .ready)
        #expect(bootstraps.count == 0)
    }

    @MainActor
    @Test("while no player is chosen, a supported player opening brings the welcome window back")
    func playerLaunchWhileWaiting() {
        let (sut, bootstraps) = makeSUT(chosenPlayer: nil)
        #expect(!sut.isShowingPlayerChooser)

        sut.handleApplicationDidLaunch(bundleIdentifier: Players.second)
        #expect(sut.isShowingPlayerChooser)
        #expect(bootstraps.count == 0)

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
    @Test("the chosen player is left out of Settings → Apps and the ignored apps")
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
    @Test("only the chosen player's audio is the music; other players count like any app")
    func onlyChosenPlayerIsProtected() {
        let (sut, _) = makeSUT()
        let configuration = sut.currentConfiguration
        #expect(!configuration.isMediaSource(Players.first))
        #expect(configuration.isMediaSource(Players.second))
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
        #expect(sut.status.health == .needsPlayer("Choose a music player"))
    }

    @MainActor
    @Test("while the player needs a permission, starting is tried again every few seconds")
    func retriesWhilePermissionMissing() async {
        let scratch = Scratch()
        // The real bootstrap stops at the permission check, before monitoring anything.
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil, realBootstrap: true)
        sut.chooseMusicPlayer(Players.first)
        for _ in 0..<200 where await scratch.first.verifyCallCount < 3 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(await scratch.first.verifyCallCount >= 3)
        #expect(sut.status.health == .needsPermission(.automation(player: "First")))
        // Logged as an error once; the repeats are the same problem.
        #expect(sut.loggedStartupProblem == "First: \(MusicPlayerError.automationPermissionDenied.localizedDescription)")
    }

    @MainActor
    @Test("a busy or hung player is asked again by itself, less and less often")
    func retriesWhilePlayerNotResponding() async {
        let scratch = Scratch()
        await scratch.second.setFailVerify(MusicPlayerError.playerNotResponding)
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil, realBootstrap: true)
        sut.chooseMusicPlayer(Players.second)
        for _ in 0..<200 where await scratch.second.verifyCallCount < 3 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(await scratch.second.verifyCallCount >= 3)
        #expect(sut.status.health == .retrying("Second is not responding"))
        #expect(sut.status.canRetry) // the menu offers Retry too
    }

    @MainActor
    @Test("a player that isn't running isn't asked again until it opens")
    func noRetryWhilePlayerNotRunning() async {
        let scratch = Scratch()
        await scratch.second.setFailVerify(MusicPlayerError.playerNotRunning)
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil, realBootstrap: true)
        sut.chooseMusicPlayer(Players.second)
        for _ in 0..<1000 where sut.status.health == .starting { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(await scratch.second.verifyCallCount == 1)
        #expect(sut.status.health == .degraded("Second is not running"))
        #expect(!sut.status.canRetry)
    }

    @MainActor
    @Test("Diagnostics in Settings follows what AutoHush sees")
    func diagnostics() {
        let (sut, _) = makeSUT()
        #expect(sut.settingsModel.diagnostics == nil)
        sut.refreshDiagnostics()
        let diagnostics = sut.settingsModel.diagnostics
        #expect(diagnostics?.apps.isEmpty == true) // nothing is monitored in tests
        #expect(diagnostics?.text.contains("Apps with Sound\nNo foreign audio output currently detected.") == true)
        #expect(diagnostics?.sections.first?.rows.first?.value.hasPrefix("First") == true)
        #expect(diagnostics?.text.contains("Automation for First") == true)
    }

    @Test("the waits between automatic starts double up to a ceiling")
    func retryDelays() {
        #expect((1...6).map { AppDelegate.retryDelay(afterFailedStarts: $0, delays: 5...60) } == [5, 10, 20, 40, 60, 60])
    }

    @MainActor
    @Test("only the chosen player is ever asked for permission to control it, and only once chosen")
    func onlyChosenPlayerIsAsked() async {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil, realBootstrap: true)

        // Nothing is asked before a player is chosen, not even when one opens.
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first)
        await Task.yield()
        #expect(await scratch.first.verifyCallCount == 0)
        #expect(await scratch.second.verifyCallCount == 0)

        sut.chooseMusicPlayer(Players.second) // also closes the welcome window
        for _ in 0..<1000 where sut.status.health == .starting { await Task.yield() }
        #expect(sut.status.health == .needsPermission(.automation(player: "Second")))
        #expect(await scratch.second.verifyCallCount == 1)
        #expect(await scratch.first.verifyCallCount == 0)
    }

    @MainActor
    @Test("a chosen player that was uninstalled is reported as not installed")
    func chosenPlayerUninstalled() async {
        let scratch = Scratch()
        scratch.installed = []
        // The real bootstrap stops at the install check, before scripting the player.
        let (sut, _) = makeSUT(scratch, realBootstrap: true)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first)
        for _ in 0..<1000 where sut.status.health == .starting { await Task.yield() }
        #expect(sut.status.health == .degraded("First is not installed"))

        // Installed again: it's controlled afresh as soon as AutoHush notices.
        scratch.installed = [Players.first]
        sut.refreshPlayerOptions()
        for _ in 0..<1000 where sut.status.health != .needsPermission(.automation(player: "First")) {
            await Task.yield()
        }
        #expect(sut.status.health == .needsPermission(.automation(player: "First")))
        #expect(await scratch.first.verifyCallCount == 1)
    }

    @MainActor
    @Test("the chosen player uninstalled while AutoHush runs is noticed without a restart, and put back starts it again")
    func playerUninstalledWhileRunning() async {
        let scratch = Scratch()
        let (sut, bootstraps) = makeSUT(scratch)
        sut.setHealth(.ready)
        sut.apply(.playback(.musicPlaying))

        // Moved to the Trash: its folder changes, and nothing else happens.
        scratch.installed = []
        scratch.changeFolder()
        for _ in 0..<1000 where sut.status.health == .ready { await Task.yield() }
        #expect(sut.status.health == .degraded("First is not installed"))
        #expect(sut.status.playback == .unknown)
        #expect(bootstraps.count == 0)

        // Put back: controlled afresh.
        scratch.installed = [Players.first]
        scratch.changeFolder()
        for _ in 0..<1000 where bootstraps.count == 0 { await Task.yield() }
        #expect(sut.status.health == .starting)
        #expect(bootstraps.count == 1)
    }

    @MainActor
    @Test("opening the menu notices a player that was uninstalled while it wasn't running")
    func menuNoticesUninstalledPlayer() {
        let scratch = Scratch()
        let (sut, bootstraps) = makeSUT(scratch)
        sut.setHealth(.degraded("First is not running"))

        scratch.installed = []
        sut.refreshPlayerOptions() // what opening the menu or Settings does
        #expect(sut.status.health == .degraded("First is not installed"))
        #expect(sut.status.playerOptions.first { $0.bundleID == Players.first }?.isInstalled == false)

        // Asked again, it stays as it is.
        sut.refreshPlayerOptions()
        #expect(sut.status.health == .degraded("First is not installed"))
        #expect(bootstraps.count == 0)
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

    @MainActor
    @Test("a pipeline torn down leaves no playback state behind, so no stale pause is handed over")
    func playbackStateEndsWithPipeline() async {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch, realBootstrap: true)
        sut.apply(.playback(.pausedByMonitor))

        // The other player's start stops at the permission check.
        sut.chooseMusicPlayer(Players.second)
        for _ in 0..<1000 where sut.status.health == .starting { await Task.yield() }
        #expect(sut.status.playback == .unknown)
        #expect(sut.status.detection == .pending)
        #expect(sut.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        #expect(scratch.preferences.pauseHandover == nil)
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
        #expect(!scratch.learningWindow.isVisible) // waits for the welcome window

        scratch.chooser.close() // closed instead of Done: the same
        sut.followWelcomeClosed()
        #expect(!sut.settingsModel.welcomeAsksPermissions)
        #expect(scratch.learningWindow.isVisible)
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
    @Test("a missing permission's button opens the player, asks macOS, or opens System Settings, as it stands")
    func permissionRequests() async {
        let scratch = Scratch()
        scratch.audio = .denied
        let (sut, _) = makeSUT(scratch)

        // Automation with the player closed: the button opens it.
        sut.requestPermission(.automation(player: "First"))
        await waitFor { !scratch.opened.isEmpty }
        #expect(scratch.opened.map(\.lastPathComponent) == ["\(Players.first).app"])

        // Accessibility: macOS's prompt, then System Settings.
        scratch.trusted = false
        sut.requestPermission(.accessibility(player: "Safari"))
        await waitFor { scratch.asked.count == 2 }
        #expect(scratch.asked == ["prompt accessibility", "open Privacy_Accessibility"])

        // Audio Recording turned down: System Settings, then AutoHush is to be reopened.
        sut.requestPermission(.systemAudioRecording)
        await waitFor { scratch.asked.count == 3 }
        #expect(scratch.asked.last == "open Privacy_AudioCapture")
        #expect(sut.status.awaitsReopenForAudioRecording)
        await sut.refreshPermissions()
        #expect(sut.settingsModel.permissions.audio == .needsReopen)

        // Never asked: macOS's own prompt.
        scratch.audio = .notDetermined
        sut.requestPermission(.systemAudioRecording)
        await waitFor { scratch.asked.count == 4 }
        #expect(scratch.asked.last == "ask audio")
    }

    // MARK: - Permissions while running

    @MainActor
    @Test("a permission taken away while monitoring runs is noticed when another app starts playing, and starts over")
    func lostPermissionNoticedWhenOthersPlay() async {
        let scratch = Scratch() // its players refuse Automation
        let (sut, bootstraps) = makeSUT(scratch)
        sut.setHealth(.ready)

        sut.apply(.activeSources([AudioSource(id: "org.videolan.vlc", name: "VLC")]))
        await waitFor { bootstraps.count == 1 }
        #expect(bootstraps.count == 1)

        // Still playing: not checked again.
        sut.apply(.activeSources([AudioSource(id: "org.videolan.vlc", name: "VLC"), AudioSource(id: "com.apple.Safari", name: "Safari")]))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await scratch.first.verifyCallCount == 1)
    }

    @MainActor
    @Test("checking control access starts over only for a missing permission, and only while monitoring runs")
    func controlAccessCheck() async {
        let scratch = Scratch()
        let (sut, bootstraps) = makeSUT(scratch)

        sut.checkControlAccess() // not monitoring yet
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await scratch.first.verifyCallCount == 0)

        sut.setHealth(.ready)
        for error: MusicPlayerError? in [nil, .playerNotRunning, .playerNotResponding] {
            await scratch.first.setFailVerify(error)
            let calls = await scratch.first.verifyCallCount
            sut.checkControlAccess()
            for _ in 0..<200 { if await scratch.first.verifyCallCount > calls { break }; try? await Task.sleep(for: .milliseconds(10)) }
            try? await Task.sleep(for: .milliseconds(30))
        }
        #expect(bootstraps.count == 0)

        await scratch.first.setFailVerify(MusicPlayerError.accessibilityPermissionDenied)
        sut.checkControlAccess()
        await waitFor { bootstraps.count == 1 }
        #expect(bootstraps.count == 1)
    }

    @MainActor
    @Test("after going to allow audio recording in System Settings, the menu offers to reopen AutoHush; other permissions don't")
    func audioRecordingOffersReopen() async {
        let scratch = Scratch()
        scratch.running = [Players.first]
        scratch.automationStatus = OSStatus(errAEEventNotPermitted)
        scratch.audio = .denied
        let (sut, _) = makeSUT(scratch)
        sut.requestPermission(.automation(player: "First"))
        await waitFor { !scratch.asked.isEmpty }
        #expect(scratch.asked == ["open Privacy_Automation"])
        #expect(!sut.status.awaitsReopenForAudioRecording)
        sut.requestPermission(.systemAudioRecording)
        await waitFor { scratch.asked.count == 2 }
        #expect(scratch.asked.last == "open Privacy_AudioCapture")
        #expect(sut.status.awaitsReopenForAudioRecording)
    }

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

    // MARK: - Auto-pause and ignored apps

    @MainActor
    @Test("toggling auto-pause switches it off and on again, and persists")
    func toggleAutoPause() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        #expect(sut.status.autoPause == .on)

        sut.toggleAutoPause()
        #expect(sut.status.autoPause == .off)
        #expect(scratch.preferences.autoPause == AutoPauseSetting(isEnabled: false))

        sut.toggleAutoPause()
        #expect(sut.status.autoPause == .on)
    }

    @MainActor
    @Test("snoozing turns auto-pause off until the end; toggling ends the snooze")
    func snoozeThenToggle() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let now = Date()

        sut.snooze(.oneHour, now: now)
        guard case .snoozed = sut.status.autoPause else {
            Issue.record("expected snoozed, got \(sut.status.autoPause)")
            return
        }
        #expect(scratch.preferences.autoPause.snoozedUntil == AutoPauseSnooze.oneHour.endDate(from: now))

        sut.toggleAutoPause(now: now)
        #expect(sut.status.autoPause == .on)
        #expect(scratch.preferences.autoPause.snoozedUntil == nil)
    }

    @MainActor
    @Test("an expired snooze is cleared at launch")
    func expiredSnoozeCleared() {
        let scratch = Scratch()
        scratch.preferences.autoPause = AutoPauseSetting(isEnabled: true, snoozedUntil: Date().addingTimeInterval(-60))
        let (sut, _) = makeSUT(scratch)
        #expect(sut.status.autoPause == .on)
        #expect(scratch.preferences.autoPause.snoozedUntil == nil)
    }

    @MainActor
    @Test("ignoring and un-ignoring an app updates the menu and the preferences")
    func ignoreApp() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")

        sut.setIgnored(vlc, true)
        #expect(sut.status.ignoredApps == [AudioSource(id: "org.videolan.vlc", name: "VLC")])
        #expect(scratch.preferences.ignoredApps.map(\.id) == ["org.videolan.vlc"])

        sut.setIgnored(vlc, false)
        #expect(sut.status.ignoredApps.isEmpty)
        #expect(scratch.preferences.ignoredApps.isEmpty)
    }

    @MainActor
    @Test("switching an app keeps its place in the order apps played; the order chosen is kept")
    func ignoringKeepsPlayedOrder() {
        let scratch = Scratch()
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome", bundlePath: "/Applications/Google Chrome.app")
        scratch.preferences.recordSeen([vlc])
        scratch.preferences.recordSeen([chrome])
        scratch.preferences.appListOrder = AppListOrder(criterion: .lastPlayed, isReversed: true)
        let (sut, _) = makeSUT(scratch)
        #expect(sut.settingsModel.appListOrder.isReversed)
        #expect(sut.settingsModel.apps.map(\.id) == [vlc.id, chrome.id])

        sut.setIgnored(vlc, true)
        #expect(scratch.preferences.seenApps == [chrome, vlc])
        #expect(sut.settingsModel.apps.map(\.id) == [vlc.id, chrome.id])

        sut.settingsModel.setAppListOrder(AppListOrder(criterion: .state))
        #expect(scratch.preferences.appListOrder == AppListOrder(criterion: .state))
        #expect(sut.settingsModel.apps.map(\.id) == [chrome.id, vlc.id])
    }

    // MARK: - Settings and updates

    @MainActor
    @Test("the Settings model mirrors auto-pause, apps and timings")
    func settingsModelMirrorsState() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")

        sut.snooze(.oneHour)
        #expect(!sut.settingsModel.isAutoPauseOn)
        #expect(sut.settingsModel.autoPauseNote?.hasPrefix("Turned off until") == true)
        sut.setAutoPause(true)
        #expect(sut.settingsModel.isAutoPauseOn && sut.settingsModel.autoPauseNote == nil)

        sut.setIgnored(vlc, true)
        #expect(sut.settingsModel.apps.map(\.id) == ["org.videolan.vlc"])
        #expect(sut.settingsModel.apps.first?.isIgnored == true)

        sut.setTimings(TimingSettings(stopGrace: 4))
        #expect(scratch.preferences.timings.stopGrace == 4)
        #expect(sut.settingsModel.timings.stopGrace == 4)
    }

    @MainActor
    @Test("forgetting an ignored app un-ignores it and removes it from the list")
    func forgetApp() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        sut.setIgnored(vlc, true)

        sut.forget(vlc)
        #expect(sut.status.ignoredApps.isEmpty)
        #expect(scratch.preferences.seenApps.isEmpty)
        #expect(sut.settingsModel.apps.isEmpty)
    }

    @MainActor
    @Test("resetting the list forgets every app and ignores none")
    func forgetAllApps() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome", bundlePath: "/Applications/Google Chrome.app")
        scratch.preferences.recordSeen([chrome])
        sut.setIgnored(vlc, true)
        #expect(sut.settingsModel.apps.count == 2)

        sut.forgetAllApps()
        #expect(sut.status.ignoredApps.isEmpty)
        #expect(scratch.preferences.ignoredApps.isEmpty)
        #expect(scratch.preferences.seenApps.isEmpty)
        #expect(sut.settingsModel.apps.isEmpty)
    }

    @MainActor
    @Test("with nothing monitored, quitting doesn't wait")
    func quitsAtOnceWithoutPipeline() {
        let (sut, _) = makeSUT()
        #expect(sut.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }

    @Test("startup retries only while the player is not ready yet")
    func transientStartupErrors() {
        #expect(AppDelegate.isTransientStartupError(MusicPlayerError.playerNotResponding))
        #expect(AppDelegate.isTransientStartupError(MusicPlayerError.playerNotRunning))
        #expect(!AppDelegate.isTransientStartupError(MusicPlayerError.automationPermissionDenied))
        #expect(!AppDelegate.isTransientStartupError(MusicPlayerError.playerCommandFailed("OSStatus -50")))
        #expect(!AppDelegate.isTransientStartupError(StubError.failed))
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
    @Test("turning automatic update checks off is saved and shown in Settings")
    func automaticChecksSetting() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        sut.setChecksForUpdatesAutomatically(false)
        #expect(!scratch.preferences.checksForUpdatesAutomatically)
        #expect(!sut.settingsModel.checksForUpdatesAutomatically)
        #expect(!sut.updates.isCheckDue())
    }

    @MainActor
    @Test("a pause handed over by the AutoHush before is taken over once, and only when recent")
    func pauseHandover() {
        let now = Date()
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        // Handed over after launch, as a copy that quits for this one does.
        scratch.preferences.pauseHandover = PauseHandover(at: now.addingTimeInterval(-5), player: nil)
        #expect(sut.takesOverPause(now: now))
        #expect(scratch.preferences.pauseHandover == nil) // read once
        scratch.preferences.pauseHandover = PauseHandover(at: now, player: nil)
        #expect(!sut.takesOverPause(now: now)) // only the first monitoring takes one over

        let stale = Scratch()
        stale.preferences.pauseHandover = PauseHandover(
            at: now.addingTimeInterval(-(AppDelegate.pauseHandoverMaxAge + 1)), player: nil
        )
        #expect(!makeSUT(stale).0.takesOverPause(now: now))
        #expect(!makeSUT().0.takesOverPause(now: now))
    }

    @MainActor
    @Test("a pause handed over for another player than the one chosen now isn't taken over")
    func pauseHandoverForAnotherPlayer() {
        let now = Date()
        let other = Scratch()
        // The player was changed outside the app meanwhile.
        other.preferences.pauseHandover = PauseHandover(at: now.addingTimeInterval(-5), player: Players.second)
        #expect(!makeSUT(other, chosenPlayer: Players.first).0.takesOverPause(now: now))
        #expect(other.preferences.pauseHandover == nil)

        let same = Scratch()
        same.preferences.pauseHandover = PauseHandover(at: now.addingTimeInterval(-5), player: Players.first)
        #expect(makeSUT(same, chosenPlayer: Players.first).0.takesOverPause(now: now))
    }

    @MainActor
    @Test("quitting while holding a pause hands it over for the chosen player")
    func pauseHandedOverOnQuit() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch, chosenPlayer: Players.first)
        sut.apply(.playback(.pausedByMonitor))
        _ = sut.applicationShouldTerminate(NSApplication.shared)
        #expect(scratch.preferences.pauseHandover?.player == Players.first)
    }

    @MainActor
    @Test("the update choice is saved and shown in Settings; it starts at installing")
    func automaticUpdatesSetting() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        #expect(sut.settingsModel.automaticUpdates == .install)
        #expect(sut.settingsModel.updateInstallNote == nil)
        sut.setAutomaticUpdates(.install)
        #expect(scratch.notifier.permissionRequests == 0)
        sut.setAutomaticUpdates(.download)
        #expect(scratch.preferences.automaticUpdates == .download)
        #expect(sut.settingsModel.automaticUpdates == .download)
        #expect(sut.updates.mode == .download)
        #expect(scratch.notifier.permissionRequests == 1) // a choice that notifies asks, if not answered yet
    }

    @MainActor
    @Test("when notifications go off, Settings shows the choice moved to installing, with checks off")
    func notificationsOffShownInSettings() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        sut.setAutomaticUpdates(.download)
        #expect(sut.updates.adapt(toNotificationsOff: true))
        #expect(sut.settingsModel.automaticUpdates == .install)
        #expect(!sut.settingsModel.checksForUpdatesAutomatically)
        #expect(scratch.preferences.automaticUpdates == .install)
        #expect(!scratch.preferences.checksForUpdatesAutomatically)
    }

    @MainActor
    @Test("Settings says why AutoHush can't update itself")
    func installUnavailableNote() {
        let (sut, _) = makeSUT(updateInstaller: MockUpdateInstaller(unavailability: .readOnlyLocation))
        #expect(sut.settingsModel.updateInstallNote == "AutoHush can't update itself, because it can't write to the folder it's in.")
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
