import AppKit
import Foundation
import Testing
import AutoHushKit
@testable import TidalSupport

/// Stands in for TIDAL's Playback menu: its Play/Pause item toggles when pressed.
private final class FakeMenu: TidalMenu, @unchecked Sendable {
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
    var trusted: Bool {
        get { lock.withLock { _trusted } }
        set { lock.withLock { _trusted = newValue } }
    }
    var found: Bool {
        get { lock.withLock { _found } }
        set { lock.withLock { _found = newValue } }
    }
    /// How often the menu was read: each read checks Accessibility first.
    var reads: Int { lock.withLock { prompts.count } }

    func isTrusted(prompt: Bool) -> Bool {
        lock.withLock {
            prompts.append(prompt)
            return _trusted
        }
    }

    func toggle(pid: pid_t) -> TidalToggle? {
        lock.withLock { _found ? TidalToggle(title: _title, isEnabled: _enabled) : nil }
    }

    func pressToggle(pid: pid_t) -> Bool {
        lock.withLock {
            presses += 1
            _title = _title == "Pause" ? "Play" : "Pause"
            return true
        }
    }
}

@Suite("TIDAL")
struct TidalTests {
    private static let labels = TidalLabels(play: ["Play", "Reproducir"], pause: ["Pause", "Pausa"])

    private func player(_ menu: FakeMenu, running: Bool = true) -> TidalPlayer {
        TidalPlayer(menu: menu, processIdentifier: { running ? 4242 : nil }, labels: { Self.labels })
    }

    // MARK: - Labels

    @Test("TIDAL's words for Play and Pause are found in every language, escapes decoded")
    func labelsFromTranslations() {
        let tables = #"""
        {"t-pause": "Pause", "t-play": "Play", "t-playback": "Playback"}
        …binary…{"t-pause": "Пауза","t-play":"Пусни"}
        {"t-play": "Lecture", "t-pause": "Pause"} "t-play": "Réproduire"
        """#
        let labels = TidalLabels.find(in: Data(tables.utf8))
        #expect(labels.play == ["Play", "Пусни", "Lecture", "Re\u{301}produire"])
        #expect(labels.pause == ["Pause", "Пауза"])
    }

    @Test("the item's title tells the state; a title in both lists, or neither, tells nothing", arguments: [
        ("Pause", PlayerState.playing), ("Pausa", .playing), ("Play", .paused), ("Reproducir", .paused), ("Shuffle", .unknown),
    ])
    func stateFromTitle(title: String, state: PlayerState) {
        #expect(TidalPlayer.state(of: TidalToggle(title: title, isEnabled: true), labels: Self.labels) == state)
        let ambiguous = TidalLabels(play: [title], pause: [title])
        #expect(TidalPlayer.state(of: TidalToggle(title: title, isEnabled: true), labels: ambiguous) == .unknown)
    }

    // MARK: - The player

    @Test("TIDAL is named and identified, and has no volume to fade")
    func identity() async {
        let tidal = player(FakeMenu())
        #expect(tidal.name == "TIDAL")
        #expect(tidal.bundleID == "com.tidal.desktop")
        #expect(tidal.volumeCurve == .linear)
        #expect(!tidal.canFade)
        #expect(await tidal.volume() == nil)
    }

    @Test("its state comes from the menu: not running, no access, logged out, playing, paused")
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
        let tidal = player(menu)
        try await tidal.pause()
        #expect(menu.presses == 1 && menu.title == "Play")
        try await tidal.pause() // already paused
        #expect(menu.presses == 1)
        try await tidal.play()
        #expect(menu.presses == 2 && menu.title == "Pause")
        try await tidal.play() // already playing
        #expect(menu.presses == 2)
    }

    @Test("with its state unknown, nothing is pressed")
    func unknownStateIsNotPressed() async {
        let menu = FakeMenu(title: "Shuffle")
        await #expect(throws: MusicPlayerError.self) { try await player(menu).pause() }
        #expect(menu.presses == 0)
    }

    @Test("checking access: TIDAL must run, Accessibility be granted (asked for once) and the menu be there")
    func verify() async {
        await #expect(throws: MusicPlayerError.playerNotRunning) { try await player(FakeMenu(), running: false).verifyControlAccess() }

        let untrusted = FakeMenu(trusted: false)
        let tidal = player(untrusted)
        await #expect(throws: MusicPlayerError.accessibilityPermissionDenied) { try await tidal.verifyControlAccess() }
        await #expect(throws: MusicPlayerError.accessibilityPermissionDenied) { try await tidal.verifyControlAccess() }
        #expect(untrusted.prompts == [true, false]) // macOS's request shows once

        let noMenu = FakeMenu()
        noMenu.found = false
        await #expect(throws: MusicPlayerError.playerCommandFailed("TIDAL's Playback menu wasn't found")) {
            try await player(noMenu).verifyControlAccess()
        }
        await #expect(throws: Never.self) { try await player(FakeMenu()).verifyControlAccess() }
    }

    // MARK: - The observer

    @MainActor
    @Test("the observer reports changes of the menu, and TIDAL quitting; nothing after stop")
    func observer() async throws {
        let menu = FakeMenu(title: "Pause")
        let workspace = NotificationCenter()
        var states: [PlayerState] = []
        let observer = TidalStateObserver(player: player(menu), workspaceCenter: workspace, interval: .milliseconds(20)) {
            states.append($0)
        }
        observer.start()
        for _ in 0..<100 where states.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        menu.title = "Play"
        for _ in 0..<100 where states.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(states == [.playing, .paused])

        observer.stop()
        menu.title = "Pause"
        try await Task.sleep(for: .milliseconds(100))
        #expect(states == [.playing, .paused])
    }

    @MainActor
    @Test("an observer let go of without stop() stops reading the menu")
    func observerReleased() async throws {
        let menu = FakeMenu()
        var observer: TidalStateObserver? = TidalStateObserver(player: player(menu), interval: .milliseconds(10)) { _ in }
        observer?.start()
        for _ in 0..<100 where menu.reads == 0 { try await Task.sleep(for: .milliseconds(5)) }
        observer = nil
        try await Task.sleep(for: .milliseconds(50)) // a read under way finishes
        let reads = menu.reads
        try await Task.sleep(for: .milliseconds(100))
        #expect(menu.reads == reads)
    }

    // MARK: - Labels of an app

    @Test("the words are read from the copy asked for, and again for another copy or version")
    func labelsOfApp() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TidalLabels-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        func app(_ name: String, version: String, play: String) throws -> URL {
            let url = folder.appending(path: "\(name).app")
            let resources = url.appending(path: "Contents/Resources")
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            try Data(#"{"t-play": "\#(play)", "t-pause": "Pause"}"#.utf8).write(to: resources.appending(path: "app.asar"))
            let info: [String: Any] = ["CFBundleShortVersionString": version, "CFBundleIdentifier": "com.example.\(name)"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: url.appending(path: "Contents/Info.plist"))
            return url
        }
        let running = try app("Running", version: "2.0", play: "Play")
        let other = try app("Other", version: "1.0", play: "Reproducir")
        #expect(TidalLabels.labels(ofAppAt: running)?.play == ["Play"])
        #expect(TidalLabels.labels(ofAppAt: other)?.play == ["Reproducir"])
        #expect(TidalLabels.labels(ofAppAt: running)?.play == ["Play"])
    }
}
