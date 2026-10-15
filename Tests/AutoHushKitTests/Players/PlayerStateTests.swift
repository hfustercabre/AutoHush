import Testing
@testable import AutoHushKit

@Suite("PlayerState")
struct PlayerStateTests {
    @Test("a toggle is pressed only from the state it leaves; in the other one, nothing; otherwise it says why")
    func needsToggle() throws {
        #expect(try PlayerState.playing.needsToggle(from: .playing))
        #expect(try PlayerState.paused.needsToggle(from: .paused))
        #expect(try !PlayerState.paused.needsToggle(from: .playing)) // paused already
        #expect(try !PlayerState.playing.needsToggle(from: .paused)) // playing already
        #expect(throws: MusicPlayerError.playerCommandFailed(.nothingToPlay)) { try PlayerState.stopped.needsToggle(from: .paused) }
        #expect(throws: MusicPlayerError.playerCommandFailed(.stateUnknown)) { try PlayerState.unknown.needsToggle(from: .playing) }
        #expect(throws: MusicPlayerError.playerNotRunning) { try PlayerState.notRunning.needsToggle(from: .paused) }
    }
}
