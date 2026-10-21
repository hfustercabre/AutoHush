import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("Preferences")
@MainActor
struct PreferencesTests {
    @Test("the learned buttons of web apps that are gone are forgotten, the others kept")
    func forgetsWebAppButtons() {
        let store = InMemoryPreferenceStore()
        let preferences = Preferences(store: store)
        preferences.forgetWebAppButtons { _ in true } // nothing stored: nothing to do
        #expect(store.object(forKey: Preferences.webAppButtonsKey) == nil)
        store.set(["A": ["play": "Play"], "B": ["play": "Play"]], forKey: Preferences.webAppButtonsKey)
        preferences.forgetWebAppButtons { $0 == "B" }
        #expect((store.object(forKey: Preferences.webAppButtonsKey) as? [String: Any]).map { Array($0.keys) } == ["A"])
    }

    @Test("auto-pause defaults to enabled without snooze")
    func defaults() {
        let store = InMemoryPreferenceStore() // shared by the Preferences below, as kept on disk
        #expect(Preferences(store: store).autoPause == AutoPauseSetting())
        #expect(Preferences(store: store).ignoredApps.isEmpty)
    }

    /// Everything AutoHush 0.12.1 keeps, as it writes it: the keys, the keys
    /// inside each value and the stored names of choices. Renaming one would
    /// reset that setting for everyone updating, every other test passing.
    @Test("settings saved by 0.12.1 load as they were")
    func savedBy0121() {
        let store = InMemoryPreferenceStore()
        let snoozedUntil = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let checked = snoozedUntil.addingTimeInterval(-3600)
        let downloaded = snoozedUntil.addingTimeInterval(-7200)
        let handedOver = snoozedUntil.addingTimeInterval(-60)
        let sha256 = String(repeating: "ab", count: 32)
        let saved: [String: Any] = [
            "autoPauseEnabled": true,
            "autoPauseSnoozedUntil": snoozedUntil,
            "ignoredApps": ["us.zoom.xos": "zoom.us", "com.example.chat": "Chat"],
            "seenApps": [
                ["id": "com.example.chat", "name": "Chat", "path": "/Applications/Chat.app"],
                ["id": "com.example.daemon", "name": "daemon"],
            ],
            "appListOrder": "name",
            "appListOrderReversed": true,
            "timings": [
                "startConfirmation": 1.5, "stopGrace": 4, "silenceThresholdDB": -50,
                "fadeOutDuration": 2.5, "fadeInDuration": 3, "fadesEnabled": 0,
                "levelsMusic": 1, "staysPausedAfterCalls": 1,
            ] as [String: Double],
            "checksForUpdatesAutomatically": false,
            "automaticUpdates": "download",
            "lastUpdateCheck": checked,
            "downloadedUpdate": ["version": "0.12.2", "sha256": sha256, "downloadedAt": downloaded] as [String: Any],
            "expiredUpdateVersion": "0.12.0",
            "lastUpdateNotice": "downloaded 0.12.2",
            "lastLaunchedVersion": "0.12.1",
            "pauseHandedOverAt": handedOver,
            "pauseHandedOverPlayer": [
                "at": handedOver, "player": "com.example.jukebox", "chosen": true, "held": ["com.example.radio"],
            ] as [String: Any],
            "detectionMethod": "askApps",
            "playbackAssertions": ["com.example.browser": ["system": ["Playing audio"], "display": ["Video Wake Lock"]]],
            "musicPlayer": "com.example.jukebox",
            "playerChoiceIntroduced": true,
            "webAppPlayPauseButtons": ["com.apple.Safari.WebApp.A": ["play": "Play"], "com.apple.Safari.WebApp.B": ["play": "Play"]],
        ]
        for (key, value) in saved { store.set(value, forKey: key) }

        let preferences = Preferences(store: store)
        #expect(preferences.autoPause == AutoPauseSetting(isEnabled: true, snoozedUntil: snoozedUntil))
        #expect(preferences.focusAutoPause == nil)
        #expect(preferences.ignoredApps == [AudioSource(id: "com.example.chat", name: "Chat"), AudioSource(id: "us.zoom.xos", name: "zoom.us")])
        #expect(preferences.appsIgnoredByDefault.isEmpty)
        #expect(preferences.seenApps == [
            AudioSource(id: "com.example.chat", name: "Chat", bundlePath: "/Applications/Chat.app"),
            AudioSource(id: "com.example.daemon", name: "daemon"),
        ])
        #expect(preferences.appListOrder == AppListOrder(criterion: .name, isReversed: true))
        #expect(preferences.timings == TimingSettings(startConfirmation: 1.5, stopGrace: 4, silenceThresholdDB: -50,
                                                     fadeOutDuration: 2.5, fadeInDuration: 3, fadesEnabled: false,
                                                     levelsMusic: true, staysPausedAfterCalls: true))
        #expect(!preferences.checksForUpdatesAutomatically)
        #expect(preferences.automaticUpdates == .download)
        #expect(preferences.lastUpdateCheck == checked)
        #expect(preferences.downloadedUpdate == DownloadedUpdate(version: "0.12.2", sha256: sha256, downloadedAt: downloaded))
        #expect(preferences.expiredUpdateVersion == "0.12.0")
        #expect(preferences.lastUpdateNotice == "downloaded 0.12.2")
        #expect(preferences.lastLaunchedVersion == "0.12.1")
        #expect(preferences.pauseHandover == PauseHandover(at: handedOver, player: "com.example.jukebox", held: ["com.example.radio"]))
        #expect(preferences.detectionMethod == .playbackSignals)
        #expect(preferences.playbackAssertions == [
            "com.example.browser": AnnouncedAssertions(system: ["Playing audio"], display: ["Video Wake Lock"]),
        ])
        #expect(preferences.musicPlayer == "com.example.jukebox")
        preferences.forgetWebAppButtons { $0 == "com.apple.Safari.WebApp.B" }
        #expect((store.object(forKey: "webAppPlayPauseButtons") as? [String: Any]).map { Array($0.keys) } == ["com.apple.Safari.WebApp.A"])

        // What else 0.12.1 writes there, where the values above are the defaults.
        store.set(false, forKey: "autoPauseEnabled")
        store.set(nil, forKey: "autoPauseSnoozedUntil")
        #expect(preferences.autoPause == AutoPauseSetting(isEnabled: false))
        store.set(["at": handedOver, "chosen": false, "held": ["com.example.radio"]] as [String: Any], forKey: "pauseHandedOverPlayer")
        #expect(preferences.pauseHandover == PauseHandover(at: handedOver, player: nil, holdsChosen: false, held: ["com.example.radio"]))
        // The other choices' names (a default's would read as the default anyway).
        store.set("openStreams", forKey: "detectionMethod")
        #expect(preferences.detectionMethod == .openStreams)
        store.set("notify", forKey: "automaticUpdates")
        #expect(preferences.automaticUpdates == .notify)
        store.set("state", forKey: "appListOrder")
        #expect(preferences.appListOrder.criterion == .state)
        // The player could be chosen already: none is put in for the user who hasn't.
        store.set(nil, forKey: "musicPlayer")
        preferences.keepFormerPlayer("com.example.former")
        #expect(preferences.musicPlayer == nil)
    }

    @Test("auto-pause and its snooze persist")
    func autoPausePersists() {
        let store = InMemoryPreferenceStore()
        let until = Date(timeIntervalSinceReferenceDate: 1_000_000)
        Preferences(store: store).autoPause = AutoPauseSetting(isEnabled: true, snoozedUntil: until)
        #expect(Preferences(store: store).autoPause == AutoPauseSetting(isEnabled: true, snoozedUntil: until))

        Preferences(store: store).autoPause = AutoPauseSetting(isEnabled: false)
        #expect(Preferences(store: store).autoPause == AutoPauseSetting(isEnabled: false))
    }

    @Test("a Focus's note of Auto-Pause persists with its timed turn off; nil removes it")
    func focusAutoPauseNote() {
        let store = InMemoryPreferenceStore()
        let until = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(Preferences(store: store).focusAutoPause == nil)

        let note = FocusAutoPauseNote(noted: AutoPauseSetting(isEnabled: true, snoozedUntil: until), applied: false)
        Preferences(store: store).focusAutoPause = note
        #expect(Preferences(store: store).focusAutoPause == note)

        let other = FocusAutoPauseNote(noted: AutoPauseSetting(isEnabled: false), applied: true)
        Preferences(store: store).focusAutoPause = other
        #expect(Preferences(store: store).focusAutoPause == other)

        Preferences(store: store).focusAutoPause = nil
        #expect(Preferences(store: store).focusAutoPause == nil)
        for key in ["focusNotedAutoPauseEnabled", "focusNotedAutoPauseSnoozedUntil", "focusAppliedAutoPause"] {
            #expect(store.object(forKey: key) == nil)
        }
    }

    @Test("ignored apps persist with their names, sorted by name, not by ID")
    func ignoredAppsPersist() {
        let store = InMemoryPreferenceStore()
        Preferences(store: store).ignoredApps = [
            AudioSource(id: "com.google.Chrome", name: "Google Chrome"),
            AudioSource(id: "org.mozilla.firefox", name: "Firefox"),
        ]
        #expect(Preferences(store: store).ignoredApps == [
            AudioSource(id: "org.mozilla.firefox", name: "Firefox"),
            AudioSource(id: "com.google.Chrome", name: "Google Chrome"),
        ])
    }

    @Test("timings persist and are clamped")
    func timingsPersist() {
        let store = InMemoryPreferenceStore()
        #expect(Preferences(store: store).timings == .defaults)
        Preferences(store: store).timings = TimingSettings(startConfirmation: 2.5, stopGrace: 99)
        #expect(Preferences(store: store).timings == TimingSettings(startConfirmation: 2.5, stopGrace: 10))
        #expect(TimingSettings.defaults.fadeOutDuration == 1 && TimingSettings.defaults.fadeInDuration == 2)
        Preferences(store: store).timings = TimingSettings(fadeOutDuration: 0.5, fadeInDuration: 4)
        #expect(Preferences(store: store).timings.fadeOutDuration == 0.5)
        #expect(Preferences(store: store).timings.fadeInDuration == 4)
        Preferences(store: store).timings = TimingSettings(fadeOutDuration: 99, fadeInDuration: -1)
        #expect(Preferences(store: store).timings.fadeOutDuration == 5)
        #expect(Preferences(store: store).timings.fadeInDuration == 0)
    }

    @Test("fades turned off persist with their durations")
    func fadesSwitchPersists() {
        let store = InMemoryPreferenceStore()
        Preferences(store: store).timings = TimingSettings(fadeOutDuration: 2.5, fadesEnabled: false)
        #expect(Preferences(store: store).timings == TimingSettings(fadeOutDuration: 2.5, fadesEnabled: false))
    }

    @Test("Settings → Advanced's switches persist, and Resume playback turned off")
    func advancedSwitchesPersist() {
        let store = InMemoryPreferenceStore()
        let advanced = TimingSettings(resumesPlayback: false, levelsMusic: true, levelingMaxCutDB: 14, levelingMinCutDB: 5,
                                      pausesForMicrophone: true, staysPausedAfterCalls: true)
        Preferences(store: store).timings = advanced
        #expect(Preferences(store: store).timings == advanced)
    }

    @Test("timings stored before the switches keep fades on and the others off")
    func timingsFromBeforeTheSwitches() {
        let store = InMemoryPreferenceStore()
        store.set(["fadeOutDuration": 1.5], forKey: "timings") // as 0.7.0 stored them
        #expect(Preferences(store: store).timings == TimingSettings(fadeOutDuration: 1.5))
    }

    @Test("seen apps keep the most recent first, once each, up to the limit")
    func seenApps() {
        let store = InMemoryPreferenceStore()
        let preferences = Preferences(store: store)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        preferences.recordSeen([vlc])
        preferences.recordSeen([chrome])
        preferences.recordSeen([vlc])
        #expect(Preferences(store: store).seenApps == [vlc, chrome])

        preferences.recordSeen((0..<60).map { AudioSource(id: "app.\($0)", name: "App \($0)") })
        let kept = preferences.seenApps.map(\.id)
        #expect(kept.count == Preferences.seenAppsLimit)
        #expect(kept.first == "app.0")
        #expect(!kept.contains(vlc.id) && !kept.contains(chrome.id)) // the oldest go
    }

    @Test("keeping an app seen adds it at the front once, and leaves a known app where it is")
    func keepSeen() {
        let store = InMemoryPreferenceStore()
        let preferences = Preferences(store: store)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        preferences.recordSeen([vlc])
        preferences.recordSeen([chrome])

        preferences.keepSeen(vlc)
        #expect(preferences.seenApps == [chrome, vlc])
        let zoom = AudioSource(id: "us.zoom.xos", name: "zoom.us", bundlePath: "/Applications/zoom.us.app")
        preferences.keepSeen(zoom)
        #expect(preferences.seenApps == [zoom, chrome, vlc])
    }

    @Test("the apps' order defaults to the most recent first, and persists")
    func appListOrder() {
        let store = InMemoryPreferenceStore()
        let preferences = Preferences(store: store)
        #expect(preferences.appListOrder == .standard)
        #expect(preferences.appListOrder == AppListOrder(criterion: .lastPlayed, isReversed: false))

        preferences.appListOrder = AppListOrder(criterion: .state, isReversed: true)
        #expect(Preferences(store: store).appListOrder == AppListOrder(criterion: .state, isReversed: true))

        store.set("someday", forKey: "appListOrder") // from a later version
        #expect(Preferences(store: store).appListOrder == AppListOrder(criterion: .lastPlayed, isReversed: true))
    }

    @Test("update settings default to automatic checks and installs, and persist")
    func updateSettings() {
        let store = InMemoryPreferenceStore()
        let preferences = Preferences(store: store)
        #expect(preferences.checksForUpdatesAutomatically)
        #expect(preferences.automaticUpdates == .install)
        #expect(preferences.lastUpdateCheck == nil)
        let date = Date(timeIntervalSinceReferenceDate: 5_000)
        preferences.checksForUpdatesAutomatically = false
        preferences.automaticUpdates = .download
        preferences.lastUpdateCheck = date
        #expect(!Preferences(store: store).checksForUpdatesAutomatically)
        #expect(Preferences(store: store).automaticUpdates == .download)
        #expect(Preferences(store: store).lastUpdateCheck == date)

        #expect(preferences.pauseHandover == nil)
        preferences.pauseHandover = PauseHandover(at: date, player: "com.example.jukebox")
        #expect(Preferences(store: store).pauseHandover == PauseHandover(at: date, player: "com.example.jukebox"))
        preferences.pauseHandover = PauseHandover(at: date, player: nil)
        #expect(Preferences(store: store).pauseHandover == PauseHandover(at: date, player: nil))
        preferences.pauseHandover = nil
        #expect(Preferences(store: store).pauseHandover == nil)

        // Only players held paused when another was chosen.
        let held = PauseHandover(at: date, player: nil, holdsChosen: false, held: ["org.videolan.vlc", "com.example.jukebox"])
        preferences.pauseHandover = held
        #expect(Preferences(store: store).pauseHandover == held)
        let both = PauseHandover(at: date, player: "com.spotify.client", held: ["org.videolan.vlc"])
        preferences.pauseHandover = both
        #expect(Preferences(store: store).pauseHandover == both)
    }

    @Test("a handover from AutoHush 0.8.2 or earlier names no player, even with one left from before; one from 0.8.3 to 0.11.0 is the chosen player's alone")
    func pauseHandoverFromAnEarlierVersion() {
        let store = InMemoryPreferenceStore()
        let preferences = Preferences(store: store)
        let earlier = Date(timeIntervalSinceReferenceDate: 5_000)
        preferences.pauseHandover = PauseHandover(at: earlier, player: "com.example.jukebox")
        // An earlier version takes it over (clearing only the date), then hands one over itself.
        store.set(nil, forKey: "pauseHandedOverAt")
        let later = earlier.addingTimeInterval(120)
        store.set(later, forKey: "pauseHandedOverAt")
        #expect(preferences.pauseHandover == PauseHandover(at: later, player: nil))

        // 0.8.3 to 0.11.0 wrote the date and the player only.
        store.set(["at": later, "player": "com.example.jukebox"], forKey: "pauseHandedOverPlayer")
        #expect(preferences.pauseHandover == PauseHandover(at: later, player: "com.example.jukebox", holdsChosen: true, held: []))
    }

    @Test("the earlier 'install updates automatically' switch becomes the matching choice", arguments: [
        (false, AutomaticUpdates.notify), (true, .install),
    ])
    func legacyInstallSwitch(installed: Bool, choice: AutomaticUpdates) {
        let store = InMemoryPreferenceStore()
        store.set(installed, forKey: "installsUpdatesAutomatically")
        #expect(Preferences(store: store).automaticUpdates == choice)
        Preferences(store: store).automaticUpdates = .download
        #expect(store.object(forKey: "installsUpdatesAutomatically") == nil)
        #expect(Preferences(store: store).automaticUpdates == .download)
    }

    @Test("a kept download, an expired version, the last notice and the last version persist")
    func updateRecords() {
        let store = InMemoryPreferenceStore()
        let preferences = Preferences(store: store)
        #expect(preferences.downloadedUpdate == nil)
        let download = DownloadedUpdate(version: "0.3.8", sha256: String(repeating: "ab", count: 32),
                                        downloadedAt: Date(timeIntervalSinceReferenceDate: 9_000))
        preferences.downloadedUpdate = download
        preferences.expiredUpdateVersion = "0.3.7"
        preferences.lastUpdateNotice = "downloaded 0.3.8"
        preferences.lastLaunchedVersion = "0.3.6"
        let reread = Preferences(store: store)
        #expect(reread.downloadedUpdate == download)
        #expect(reread.expiredUpdateVersion == "0.3.7")
        #expect(reread.lastUpdateNotice == "downloaded 0.3.8")
        #expect(reread.lastLaunchedVersion == "0.3.6")
        preferences.downloadedUpdate = nil
        #expect(Preferences(store: store).downloadedUpdate == nil)
    }

    @Test("detection defaults to audio levels and persists")
    func detectionMethod() {
        let store = InMemoryPreferenceStore()
        #expect(Preferences(store: store).detectionMethod == .audioLevels)
        Preferences(store: store).detectionMethod = .playbackSignals
        #expect(Preferences(store: store).detectionMethod == .playbackSignals)
    }

    @Test("what AntiDot mode learns about apps is remembered; the earlier list without names is dropped")
    func playbackAssertions() {
        let store = InMemoryPreferenceStore()
        store.set(["com.google.Chrome"], forKey: "announcingApps")
        #expect(Preferences(store: store).playbackAssertions.isEmpty)

        let learned = [
            "com.google.Chrome": AnnouncedAssertions(system: ["Playing audio"], display: ["Video Wake Lock"]),
            "com.apple.Safari": AnnouncedAssertions(display: ["com.apple.WebCore: HTMLMediaElement playback"]),
        ]
        Preferences(store: store).playbackAssertions = learned
        #expect(Preferences(store: store).playbackAssertions == learned)
        #expect(store.object(forKey: "announcingApps") == nil)
    }

    @Test("the earlier 'measure audio levels: off' setting becomes open streams only")
    func legacyMeasuringOff() {
        let store = InMemoryPreferenceStore()
        store.set(false, forKey: "measuresAudioLevels")
        #expect(Preferences(store: store).detectionMethod == .openStreams)
        Preferences(store: store).detectionMethod = .audioLevels
        #expect(store.object(forKey: "measuresAudioLevels") == nil)
    }

    @Test("the chosen music player persists; none is chosen at first")
    func musicPlayer() {
        let store = InMemoryPreferenceStore()
        #expect(Preferences(store: store).musicPlayer == nil)
        Preferences(store: store).musicPlayer = "com.example.player"
        #expect(Preferences(store: store).musicPlayer == "com.example.player")
    }

    @Test("someone updating from before the choice keeps the former player")
    func updatingKeepsFormerPlayer() {
        let store = InMemoryPreferenceStore()
        store.set("0.3.11", forKey: "lastLaunchedVersion")
        Preferences(store: store).keepFormerPlayer("com.example.former")
        #expect(Preferences(store: store).musicPlayer == "com.example.former")
    }

    @Test("on a Mac where AutoHush never ran, no player is chosen, even on later launches")
    func newUserIsAsked() {
        let store = InMemoryPreferenceStore()
        let preferences = Preferences(store: store)
        preferences.keepFormerPlayer("com.example.former")
        #expect(preferences.musicPlayer == nil)
        // The first launch stores settings of its own; the user still hasn't chosen.
        preferences.lastLaunchedVersion = "0.4.0"
        preferences.keepFormerPlayer("com.example.former")
        #expect(preferences.musicPlayer == nil)
    }

    @Test("a chosen player is never replaced by the former one")
    func choiceIsKept() {
        let store = InMemoryPreferenceStore()
        let preferences = Preferences(store: store)
        preferences.lastLaunchedVersion = "0.3.11"
        preferences.musicPlayer = "com.example.chosen"
        preferences.keepFormerPlayer("com.example.former")
        #expect(preferences.musicPlayer == "com.example.chosen")
    }
}
