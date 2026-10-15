import Foundation
import Testing
@testable import CheckedPlayers
import ScriptablePlayers
import WebAppPlayers
import AutoHushKit
import AutoHushTestSupport

@Suite("CheckedPlayer")
struct CheckedPlayerTests {
    private let app = URL(fileURLWithPath: "/Applications/Jukebox.app")
    private let script = ScriptSetup(commands: .pauseAndPlay(pause: "jukePaus", play: "jukePlay"), state: .playerState, hasVolume: true)

    private func setup(_ ways: [PlayerSetup.Way]) -> PlayerSetup {
        PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox", appURL: app, ways: ways)
    }

    private func player(ways: [any MusicPlayer], signs: [any MusicPlayer], running: Bool = true) -> CheckedPlayer {
        CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: ways, signs: signs), reports: nil,
                      processIdentifier: { running ? 4242 : nil })
    }

    @Test("a setup keeps its ways the surest first, the panel last whatever the order found; and is kept as found")
    func setups() throws {
        let found = setup([.panel(rememberedRow: nil), .script(script), .page(.webKit)])
        #expect(found.ways == [.script(script), .page(.webKit), .panel(rememberedRow: nil)])
        #expect(try JSONDecoder().decode(PlayerSetup.self, from: JSONEncoder().encode(found)) == found)
    }

    @Test("muted instead of paused: a pause mutes it and it reads paused; a play unmutes it; once its assertion was seen, it tells")
    func muting() async throws {
        let muter = FakeMuter()
        let held = AssertionBox()
        let setup = setup([.mute])
        let player = CheckedPlayer(setup: setup, parts: CheckedPlayer.parts(for: setup, store: MemoryStore()), reports: nil,
                                   processIdentifier: { 4242 }, muter: muter, assertionHeld: { _ in held.value })
        #expect(player.pausesByMuting && player.controlPermission == .systemAudioRecording && !player.canFade)
        held.value = true
        #expect(await player.playerState() == .playing)
        try await player.pause()
        #expect(muter.isMuted)
        #expect(await player.playerState() == .paused) // still plays, muted: our pause
        try await player.play()
        #expect(!muter.isMuted)
        held.value = false
        #expect(await player.playerState() == .paused) // its assertion seen: without it, it's paused

        player.allowTaps(false) // AntiDot mode: no taps, no mute
        await #expect(throws: MusicPlayerError.playerCommandFailed(.muteUnavailable)) { try await player.pause() }
    }

    @Test("only an app whose page is a way and that needs the launch option can need reopening")
    func reopenNeed() async {
        let menu = CheckedPlayer(setup: setup([.menu(menuName: "Controls")]), reports: nil, store: MemoryStore())
        #expect(await menu.needsReopen() == false)
        var page = setup([.page(.webKit)])
        page.needsLaunchOption = true
        // Not running: nothing to reopen.
        #expect(await CheckedPlayer(setup: page, reports: nil, store: MemoryStore()).needsReopen() == false)
    }

    @Test("it's an app, controlled as its first way needs, faded when its script has a volume")
    func basics() {
        let scripted = CheckedPlayer(setup: setup([.script(script), .menu(menuName: "Controls")]), reports: nil, store: MemoryStore())
        #expect(scripted.kind == .checkedApp)
        #expect(scripted.controlPermission == .automation(player: "Jukebox"))
        #expect(scripted.canFade)
        let menu = CheckedPlayer(setup: setup([.menu(menuName: "Controls")]), reports: nil, store: MemoryStore())
        #expect(menu.controlPermission == .accessibility(player: "Jukebox"))
        #expect(!menu.canFade)
    }

    @Test("a press goes to the first way; one that fails hands it to the next")
    func fallsBack() async throws {
        let first = MockMusicPlayer(state: .playing), second = MockMusicPlayer(state: .playing)
        try await player(ways: [first, second], signs: [first]).pause()
        #expect(await first.pauseCallCount == 1)
        #expect(await second.pauseCallCount == 0)

        await first.setFailPause(MusicPlayerError.playerNotResponding)
        try await player(ways: [first, second], signs: [first]).pause()
        #expect(await second.pauseCallCount == 1)

        await second.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        await #expect(throws: MusicPlayerError.playerNotResponding) {
            try await player(ways: [first, second], signs: [first]).pause()
        }
    }

    @Test("its state is the surest sign that answers; not running, it isn't asked")
    func state() async {
        let script = MockMusicPlayer(state: .paused), page = MockMusicPlayer(state: .playing)
        #expect(await player(ways: [script], signs: [script, page]).playerState() == .paused)
        await script.setUnansweredStateQueries(1)
        #expect(await player(ways: [script], signs: [script, page]).playerState() == .playing)
        #expect(await player(ways: [script], signs: [script, page], running: false).playerState() == .notRunning)
    }

    @Test("only the installed apps' setups are players, each kept while its setup stays the same")
    func players() throws {
        let installed = FileManager.default.temporaryDirectory.appendingPathComponent("Checked-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: installed) }
        let store = MemoryStore()
        store.save(PlayerSetup(bundleID: "com.example.installed", name: "Installed", appURL: installed, ways: [.menu(menuName: "Play")]))
        store.save(PlayerSetup(bundleID: "com.example.gone", name: "Gone", appURL: URL(fileURLWithPath: "/nonexistent/Gone.app"),
                               ways: [.menu(menuName: "Play")]))
        let players = CheckedPlayers(store: store)
        let first = players.current()
        #expect(first.map(\.bundleID) == ["com.example.installed"])
        #expect(players.current().first === first.first)
    }
}

/// Mutes kept in memory.
final class FakeMuter: AudioMuting, @unchecked Sendable {
    private let lock = NSLock()
    private var muted: Set<pid_t> = []
    var allowed = true
    var isMuted: Bool { lock.withLock { !muted.isEmpty } }
    func mute(appPID: pid_t) -> Bool { lock.withLock { allowed ? muted.insert(appPID).inserted || true : false } }
    func unmute(appPID: pid_t) { lock.withLock { _ = muted.remove(appPID) } }
}

/// Setups kept in memory.
final class MemoryStore: PlayerSetupStore, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [String: PlayerSetup] = [:]
    func setups() -> [PlayerSetup] { lock.withLock { Array(kept.values) } }
    func save(_ setup: PlayerSetup) { lock.withLock { kept[setup.bundleID] = setup } }
    func forget(_ bundleID: String) { lock.withLock { kept[bundleID] = nil } }
}

/// Whether the app holds its keep-awake assertion, as the test says.
final class AssertionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var held = false
    var value: Bool {
        get { lock.withLock { held } }
        set { lock.withLock { held = newValue } }
    }
}
