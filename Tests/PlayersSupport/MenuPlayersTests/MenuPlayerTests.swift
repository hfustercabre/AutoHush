import AppKit
import Foundation
import Testing
import AutoHushKit
@testable import MenuPlayers
import AutoHushTestSupport

/// Stands in for an app's playback menu: its Play/Pause item toggles when pressed.
private final class FakeMenu: PlaybackMenu, @unchecked Sendable {
    private let lock = NSLock()
    private var _title: String
    private var _enabled: Bool
    private var _trusted: Bool
    private var _found = true
    private(set) var presses = 0
    private(set) var prompts: [Bool] = []

    init(title: String = "Pause", enabled: Bool = true, trusted: Bool = true) {
        _title = title
        _enabled = enabled
        _trusted = trusted
    }

    var title: String {
        get { lock.withLock { _title } }
        set { lock.withLock { _title = newValue } }
    }
    var found: Bool {
        get { lock.withLock { _found } }
        set { lock.withLock { _found = newValue } }
    }

    func isTrusted(prompt: Bool) -> Bool {
        lock.withLock {
            prompts.append(prompt)
            return _trusted
        }
    }

    func toggle(pid: pid_t) -> MenuToggle? {
        lock.withLock { _found ? MenuToggle(title: _title, isEnabled: _enabled) : nil }
    }

    func pressToggle(pid: pid_t) -> Bool {
        lock.withLock {
            presses += 1
            _title = _title == "Pause" ? "Play" : "Pause"
            return true
        }
    }
}

@Suite("MenuPlayer")
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

    @Test("a menu player is named and identified by its profile, needs Accessibility and has no volume to fade")
    func identity() async {
        let jukebox = player(FakeMenu())
        #expect(jukebox.name == "Jukebox")
        #expect(jukebox.bundleID == "com.example.jukebox")
        #expect(jukebox.controlPermission == .accessibility(player: "Jukebox"))
        #expect(jukebox.volumeCurve == .linear)
        #expect(!jukebox.canFade)
        #expect(await jukebox.volume() == nil)
        #expect(jukebox.ownWordsRead == true)
        let wordless = MenuPlayer(profile: Self.profile, menu: FakeMenu(), processIdentifier: { 4242 }, words: { nil })
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

    @Test("pause and play press the item only from the opposite state")
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
    }

    @Test("with its state unknown, nothing is pressed")
    func unknownStateIsNotPressed() async {
        let menu = FakeMenu(title: "Shuffle")
        await #expect(throws: MusicPlayerError.self) { try await player(menu).pause() }
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

    @Test("the words are read once per copy and version of the app")
    func wordsOfApp() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PlayPauseWords-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        func app(_ name: String, version: String) throws -> URL {
            let url = folder.appending(path: "\(name).app")
            try FileManager.default.createDirectory(at: url.appending(path: "Contents"), withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleShortVersionString": version, "CFBundleIdentifier": "com.example.\(name)"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: url.appending(path: "Contents/Info.plist"))
            return url
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
        #expect(reads == ["Running.app", "Other.app", "Broken.app"])
    }
}
