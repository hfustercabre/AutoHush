import Foundation
import Testing
@testable import AutoHushApp

@Suite("AppPlaying")
struct AppPlayingTests {
    private func playing(output: Bool, measured: Bool, audible: Bool) -> AppPlaying {
        AppPlaying(outputRunning: { _ in output }, levelMeasured: { measured }, audible: { _ in audible })
    }

    @Test("a paused app that keeps its output open, silent, doesn't play (Qobuz); heard, it does")
    func openSilentOutput() async {
        #expect(await playing(output: true, measured: true, audible: false).plays(42) == false)
        #expect(await playing(output: true, measured: true, audible: true).plays(42))
    }

    @Test("no output, no play; its level not measured, the open output decides")
    func withoutLevel() async {
        #expect(await playing(output: false, measured: true, audible: true).plays(42) == false)
        #expect(await playing(output: true, measured: false, audible: false).plays(42))
    }
}
