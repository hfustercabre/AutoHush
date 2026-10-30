import AppKit
import Foundation
import Testing
import AutoHushKit
@testable import MenuPlayers
import AutoHushTestSupport

/// Stands in for an app's playback menu: its Play/Pause item toggles when pressed.
private final class FakeMenu: PlaybackMenu, @unchecked Sendable {
    // Read and written only under `lock`.
    private let lock = NSLock()
    private var _title: String
    private var _enabled: Bool
    private var _trusted: Bool
    private var _found = true
    private var _pressFails = false
    private var _presses = 0
    private var _prompts: [Bool] = []

    init(title: String = "Pause", enabled: Bool = true, trusted: Bool = true) {
        _title = title
        _enabled = enabled
        _trusted = trusted
    }

    var presses: Int { lock.withLock { _presses } }
    var prompts: [Bool] { lock.withLock { _prompts } }

    var title: String {
        get { lock.withLock { _title } }
        set { lock.withLock { _title = newValue } }
    }
    var found: Bool {
        get { lock.withLock { _found } }
        set { lock.withLock { _found = newValue } }
    }
    /// Its item can't be pressed (Accessibility refuses): nothing changes.
    var pressFails: Bool {
        get { lock.withLock { _pressFails } }
        set { lock.withLock { _pressFails = newValue } }
    }

    func isTrusted(prompt: Bool) -> Bool {
        lock.withLock {
            _prompts.append(prompt)
            return _trusted
        }
    }

    func toggle(pid: pid_t) -> MenuToggle? {
        lock.withLock { _found ? MenuToggle(title: _title, isEnabled: _enabled) : nil }
    }

    func pressToggle(pid: pid_t) -> Bool {
        lock.withLock {
            guard !_pressFails else { return false }
            _presses += 1
            _title = _title == "Pause" ? "Play" : "Pause"
            return true
        }
    }
}

@Suite("MenuPlayer", .waitsTimeLimit)
struct MenuPlayerTests {
    private static let words = PlayPauseWords(play: ["Play", "Reproducir"], pause: ["Pause", "Pausa"])
    private static let profile = MenuPlayerProfile(
        bundleID: "com.example.jukebox", name: "Jukebox", menuName: "Playback", readWords: { _ in words }
    )

    private func player(_ menu: FakeMenu, running: Bool = true) -> MenuPlayer {
        MenuPlayer(profile: Self.profile, menu: menu, processIdentifier: { running ? 4242 : nil }, words: { Self.words })
    }

    @Test("the item's title tells the state; a title in both lists, or neither, tells nothing", arguments: [
        ("Pause", PlayerState.playing), ("Pausa", .playing), ("Play", .paused), ("Reproducir", .paused), ("Shuffle", .unknown),
    ])
    func stateFromTitle(title: String, state: PlayerState) {
        #expect(MenuPlayer.state(of: MenuToggle(title: title, isEnabled: true), words: Self.words) == state)
        let ambiguous = PlayPauseWords(play: [title], pause: [title])
        #expect(MenuPlayer.state(of: MenuToggle(title: title, isEnabled: true), words: ambiguous) == .unknown)
    }

    @Test("a menu player is named and identified by its profile")
    func identity() {
        let jukebox = player(FakeMenu())
        #expect(jukebox.name == "Jukebox")
        #expect(jukebox.bundleID == "com.example.jukebox")
    }

    @Test("a menu player needs Accessibility")
    func needsAccessibility() {
        #expect(player(FakeMenu()).controlPermission == .accessibility(player: "Jukebox"))
    }

    @Test("a menu player has no volume to fade")
    func noVolume() async throws {
        let jukebox = player(FakeMenu())
        #expect(jukebox.volumeCurve == .linear)
        #expect(!jukebox.canFade)
        #expect(await jukebox.volume() == nil)
        try await jukebox.setVolume(30) // nothing to set
    }

    @Test("a menu player is read about once a second")
    func readOnceASecond() {
        #expect(player(FakeMenu()).stateReportDelay == PolledStateObserver.reportDelay) // a change is seen up to a read later
    }

    @Test("without its own words, a menu player's state is unknown, and Diagnostics says so, never reading them on its own thread")
    func withoutItsWords() async {
        let jukebox = player(FakeMenu())
        #expect(await jukebox.playerState() == .playing)
        #expect(jukebox.ownWordsRead == true) // as its state's read found them
        let wordless = MenuPlayer(profile: Self.profile, menu: FakeMenu(), processIdentifier: { 4242 }, words: { nil })
        #expect(wordless.ownWordsRead == nil) // read on the player's queue, not here: nothing read yet
        #expect(await wordless.playerState() == .unknown)
        #expect(wordless.ownWordsRead == false) // Diagnostics says so
    }

    @Test("its state comes from the menu: not running, no access, nothing to play, playing, paused")
    func state() async {
        #expect(await player(FakeMenu(), running: false).playerState() == .notRunning)
        #expect(await player(FakeMenu(trusted: false)).playerState() == .unknown)
        #expect(await player(FakeMenu(enabled: false)).playerState() == .stopped)
        #expect(await player(FakeMenu(title: "Pause")).playerState() == .playing)
        #expect(await player(FakeMenu(title: "Play")).playerState() == .paused)
    }

    @Test("pause and play press the item only from the opposite state; one that can't be pressed says so")
    func neverBlindToggle() async throws {
        let menu = FakeMenu(title: "Pause")
        let jukebox = player(menu)
        try await jukebox.pause()
        #expect(menu.presses == 1 && menu.title == "Play")
        try await jukebox.pause() // already paused
        #expect(menu.presses == 1)
        try await jukebox.play()
        #expect(menu.presses == 2 && menu.title == "Pause")
        try await jukebox.play() // already playing
        #expect(menu.presses == 2)
        menu.pressFails = true
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressFailed)) { try await jukebox.pause() }
        #expect(menu.presses == 2 && menu.title == "Pause")
    }

    @Test("with its state unknown, nothing is pressed")
    func unknownStateIsNotPressed() async {
        let menu = FakeMenu(title: "Shuffle")
        await #expect(throws: MusicPlayerError.playerCommandFailed(.stateUnknown)) { try await player(menu).pause() }
        #expect(menu.presses == 0)
    }

    @Test("checking access: the app must run, Accessibility be granted (asked for once) and the menu be there")
    func verify() async {
        await #expect(throws: MusicPlayerError.playerNotRunning) { try await player(FakeMenu(), running: false).verifyControlAccess() }

        let untrusted = FakeMenu(trusted: false)
        let jukebox = player(untrusted)
        await #expect(throws: MusicPlayerError.accessibilityPermissionDenied) { try await jukebox.verifyControlAccess() }
        await #expect(throws: MusicPlayerError.accessibilityPermissionDenied) { try await jukebox.verifyControlAccess() }
        #expect(untrusted.prompts == [true, false]) // macOS's request shows once

        let noMenu = FakeMenu()
        noMenu.found = false
        await #expect(throws: MusicPlayerError.playerCommandFailed(.menuItemNotFound)) {
            try await player(noMenu).verifyControlAccess()
        }
        await #expect(throws: Never.self) { try await player(FakeMenu()).verifyControlAccess() }
    }

    @MainActor
    @Test("its state is watched by reading the menu")
    func observer() async throws {
        let menu = FakeMenu(title: "Pause")
        var states: [PlayerState] = []
        let observer = player(menu).makeStateObserver { states.append($0) }
        observer.start()
        defer { observer.stop() }
        await TestWait.until { !states.isEmpty }
        #expect(states == [.playing])
    }

    @Test("the words are read once per copy and version of the app: the copy running, else the one Launch Services knows")
    func wordsOfApp() throws {
        let folder = TemporaryFolder("MenuPlayerTests", create: false)
        func app(_ name: String, version: String) throws -> URL {
            try TestAppBundle.make(in: folder.url, name: name, info: ["CFBundleShortVersionString": version, "CFBundleIdentifier": "com.example.\(name)"])
        }
        var reads: [String] = []
        func read(_ url: URL) -> PlayPauseWords? {
            reads.append(url.lastPathComponent)
            return url.lastPathComponent == "Broken.app"
                ? PlayPauseWords(play: [], pause: ["Pause"])
                : PlayPauseWords(play: [url.lastPathComponent], pause: ["Pause"])
        }
        let running = try app("Running", version: "2.0")
        let other = try app("Other", version: "1.0")
        let broken = try app("Broken", version: "1.0")
        #expect(PlayPauseWords.words(ofAppAt: running, read: read)?.play == ["Running.app"])
        #expect(PlayPauseWords.words(ofAppAt: other, read: read)?.play == ["Other.app"])
        #expect(PlayPauseWords.words(ofAppAt: running, read: read)?.play == ["Running.app"])
        #expect(PlayPauseWords.words(ofAppAt: broken, read: read) == nil) // no words for Play
        #expect(PlayPauseWords.words(ofAppAt: broken, read: read) == nil) // not read again: Diagnostics asks often
        #expect(reads == ["Running.app", "Other.app", "Broken.app"])
        // Updated while AutoHush runs: read again.
        _ = try app("Running", version: "2.1")
        #expect(PlayPauseWords.words(ofAppAt: running, read: read)?.play == ["Running.app"])
        #expect(reads == ["Running.app", "Other.app", "Broken.app", "Running.app"])
        // By bundle ID: an app macOS knows (TextEdit, which no other test reads), none for one it doesn't.
        #expect(PlayPauseWords.installed(bundleID: "com.apple.TextEdit", read: read)?.play == ["TextEdit.app"])
        #expect(PlayPauseWords.installed(bundleID: "com.example.none-\(UUID().uuidString)", read: read) == nil)
        #expect(reads.count == 5)
        withExtendedLifetime(folder) {}
    }
}
