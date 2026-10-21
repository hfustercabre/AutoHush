import AppKit
import CheckedPlayers
import Foundation
import os
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

@Suite("AppDelegate", .waitsTimeLimit)
struct AppDelegateTests {
    /// In-memory preferences, the choices kept beside them in a suite of its
    /// own, the apps added with Add an App in memory, and a downloads folder
    /// of its own, so tests never write AutoHush's preference files or touch
    /// its real Caches. Two stand-in music players to choose from, which may
    /// be controlled, which of them are installed (the second in a folder
    /// inside /Applications), folder watches the test fires, and monitorings
    /// that stand in for the engine, so a start never taps real audio processes.
    @MainActor
    final class Scratch {
        var preferences = Preferences(store: InMemoryPreferenceStore())
        private let suite = TestDefaults("AppDelegateTests")
        lazy var defaults = suite.defaults
        let addedSetups = MemorySetupStore()
        lazy var checkedPlayers = CheckedPlayers(store: addedSetups, locate: { _ in nil })
        let launchAtLogin = MockLaunchAtLoginController(isEnabled: false)
        private let downloadsFolder = TemporaryFolder("AppDelegateTests", create: false)
        var downloads: URL { downloadsFolder.url }
        let notifier = MockUpdateNotifier()
        let first = MockMusicPlayer(bundleID: Players.first, name: "First")
        let second = MockMusicPlayer(bundleID: Players.second, name: "Second", canFade: false)
        let monitorings = FakeMonitorings()
        /// The Mac's outputs, muted for a check, and its volume, lowered for the music.
        let outputs = MockOutputMuting()
        let volume = MockSystemVolume([0: -10])
        /// The menu bar's Now Playing setting, shown for a press and hidden again.
        let nowPlaying = NowPlayingSettingInMemory()
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
        let automationGate = Gate(open: true)
        /// The clock a player's reopens are stamped by.
        let clock = ManualClock()
        /// Whether one of AutoHush's windows is open, for an update's quiet
        /// moment: as if one were, so no test's update restarts the tests' own
        /// process, unless a test says none is.
        var windowOpen = true
        lazy var permissionCenter = PermissionCenter(system: .init(
            isTrusted: { [unowned self] in self.trusted },
            promptAccessibility: { [unowned self] in self.asked.append("prompt accessibility") },
            automation: { [status = automationStatus, gate = automationGate] _, ask in
                await Self.pass(gate)
                return ask ? noErr : status
            },
            runningPID: { [unowned self] in self.running.contains($0) ? 4242 : nil },
            audio: { [unowned self] in self.audio },
            requestAudio: { [unowned self] _ in self.asked.append("ask audio") },
            openPane: { [unowned self] in self.asked.append("open \($0.rawValue)") }
        ))

        private var onFolderChange: (@MainActor () -> Void)?

        /// Waits at `gate`. A function of its own: a call to an actor written
        /// in a property's initializer, even inside a closure, is refused as
        /// isolated to that actor beside the main actor (Swift 6.4).
        private nonisolated static func pass(_ gate: Gate) async { await gate.wait() }

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
            suite.remove()
        }

        /// A web app AutoHush must learn, installed and offered beside First.
        func offerWebApp(_ status: LearningStatus) -> MockLearningPlayer {
            let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.TEST", name: "YT Music", status: status)
            players = MusicPlayerCatalog(players: [first], found: { [webApp] })
            installed.insert(webApp.bundleID)
            return webApp
        }
    }

    typealias Players = TestPlayers

    /// `chosenPlayer`: the player already chosen before this launch, if any;
    /// `addApp`: stand-ins for the apps on the Mac and the check's helper,
    /// which Add an App then works through. Returns the monitorings its
    /// starts made, too.
    @MainActor
    func makeSUT(
        _ scratch: Scratch = Scratch(),
        chosenPlayer: String? = Players.first,
        updateChecker: UpdateChecker = UpdateChecker { _ in throw URLError(.notConnectedToInternet) },
        updateInstaller: MockUpdateInstaller = MockUpdateInstaller(),
        windowWatchSleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        madeWebAppWait: Duration = .zero,
        addApp: World? = nil
    ) -> (AppDelegate, FakeMonitorings) {
        if let chosenPlayer { scratch.preferences.musicPlayer = chosenPlayer }
        let sut = AppDelegate(
            preferences: scratch.preferences,
            defaults: scratch.defaults,
            launchAtLoginController: scratch.launchAtLogin,
            updateSystem: UpdateController.System(checker: updateChecker, installer: updateInstaller, notifier: scratch.notifier,
                                                  downloadsFolder: scratch.downloads, currentVersion: AppVersion("0.2.0")),
            players: scratch.players,
            checkedPlayers: scratch.checkedPlayers,
            addAppSystem: AddAppFeature.System(outputMute: OutputMute(outputs: scratch.outputs, defaults: scratch.defaults),
                                               standIns: addApp.map { (reader: $0, helper: $0) }),
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
            retries: PlayerSession.Retries(permissionInterval: 0.05, delays: 0.02...0.08),
            watchFolder: { scratch.watch($0, onChange: $1) },
            installCheckDelay: .zero,
            permissionCenter: scratch.permissionCenter,
            windowWatchSleep: windowWatchSleep,
            clock: { scratch.clock.now },
            hasOpenWindow: { scratch.windowOpen }
        )
        return (sut, scratch.monitorings)
    }

    /// Starts monitoring the chosen player, as at launch, and waits until it runs.
    @MainActor
    func start(_ sut: AppDelegate) async {
        sut.session.launch()
        await TestWait.until { sut.status.health == .ready }
    }
}
