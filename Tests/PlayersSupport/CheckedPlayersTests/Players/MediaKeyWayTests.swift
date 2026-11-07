import Foundation
import Testing
@testable import CheckedPlayers
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("MediaKeyWay", .waitsTimeLimit)
struct MediaKeyWayTests {
    private static let pid: pid_t = 4242

    /// The key for an app in `state`, with `nowPlaying` holding Now Playing
    /// (`asked` runs as it's asked); each press counted in `presses`, and
    /// followed by the app unless `ignored`.
    private func key(_ state: Locked<PlayerState>, nowPlaying: NowPlayingApp.Answer = .process(Self.pid), presses: Locked<Int>,
                     ignored: Bool = false, asked: @escaping @Sendable () -> Void = {}) -> MediaKeyWay {
        let late = LateState()
        late.set { state.value }
        return MediaKeyWay(bundleID: "com.example.jukebox", name: "Jukebox", state: late, processIdentifier: { Self.pid },
                           nowPlaying: { asked(); return nowPlaying },
                           pressKey: {
                               presses.withLock { $0 += 1 }
                               if !ignored { state.withLock { $0 = $0 == .playing ? .paused : .playing } }
                           },
                           sleep: { _ in })
    }

    @Test("it's pressed only while macOS says the app holds Now Playing: another app, none, or no answer, it isn't")
    func nowPlaying() async throws {
        for answer in [NowPlayingApp.Answer.process(99), .none, .unknown] {
            let presses = Locked(0)
            await #expect(throws: MediaKeyWay.NotPressed.self) { try await key(Locked(.playing), nowPlaying: answer, presses: presses).pause() }
            #expect(presses.value == 0)
        }
        let presses = Locked(0), state = Locked(PlayerState.playing)
        try await key(state, presses: presses).pause()
        #expect(presses.value == 1 && state.value == .paused)
        try await key(state, presses: presses).play()
        #expect(presses.value == 2 && state.value == .playing)
    }

    @Test("it's pressed only from the opposite state: already there, nothing is pressed; its state unknown or nothing to play, it isn't either")
    func fromTheOppositeState() async throws {
        let presses = Locked(0)
        try await key(Locked(.paused), presses: presses).pause()
        try await key(Locked(.stopped), presses: presses).pause()
        try await key(Locked(.playing), presses: presses).play()
        await #expect(throws: MediaKeyWay.NotPressed.self) { try await key(Locked(.unknown), presses: presses).pause() }
        await #expect(throws: MediaKeyWay.NotPressed.self) { try await key(Locked(.stopped), presses: presses).play() }
        #expect(presses.value == 0)
    }

    @Test("its state is read again after Now Playing answers: a press before it that took meanwhile isn't undone")
    func readAgain() async throws {
        let presses = Locked(0), state = Locked(PlayerState.paused)
        try await key(state, presses: presses, asked: { state.withLock { $0 = .playing } }).play()
        #expect(presses.value == 0 && state.value == .playing)
    }

    @Test("Now Playing is asked again as its state is read again: another app that took it meanwhile doesn't get the key")
    func askedAgain() async throws {
        let presses = Locked(0), asks = Locked(0)
        let late = LateState()
        late.set { .playing }
        // The app holds Now Playing at the first ask, another app at the second.
        let way = MediaKeyWay(bundleID: "com.example.jukebox", name: "Jukebox", state: late, processIdentifier: { Self.pid },
                              nowPlaying: { asks.withLock { $0 += 1; return $0 } == 1 ? .process(Self.pid) : .process(99) },
                              pressKey: { presses.withLock { $0 += 1 } }, sleep: { _ in })
        await #expect(throws: MediaKeyWay.NotPressed.self) { try await way.pause() }
        #expect(asks.value == 2 && presses.value == 0)
    }

    @Test("a press the app doesn't follow fails, and isn't made again: a second would undo a first the app is only slow to show")
    func once() async throws {
        let presses = Locked(0)
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressIgnored)) {
            try await key(Locked(.playing), presses: presses, ignored: true).pause()
        }
        #expect(presses.value == 1)
    }

    @Test("it judges its own press by the app's signs, and tells nothing itself")
    func itself() async {
        let way = key(Locked(.playing), presses: Locked(0))
        #expect(way.checksItsPresses && !way.canFade)
        #expect(await way.playerState() == .unknown)
        #expect(await !way.statesItself())
    }
}
