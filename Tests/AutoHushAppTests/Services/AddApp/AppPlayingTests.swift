import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

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

    @Test("reading and listening block a queue of their own, never Swift's shared threads")
    func offSharedThreads() async {
        let queues = Locked<[String]>([])
        let note: @Sendable () -> Void = {
            let label = String(cString: __dispatch_queue_get_label(nil))
            queues.append(label)
        }
        let playing = AppPlaying(outputRunning: { _ in note(); return true }, levelMeasured: { note(); return true },
                                 audible: { _ in note(); return true })
        #expect(await playing.plays(42))
        #expect(queues.value == Array(repeating: "AutoHush.AppPlaying", count: 3))
    }

    @Test("no output, no play; its level not measured, the open output decides")
    func withoutLevel() async {
        #expect(await playing(output: false, measured: true, audible: true).plays(42) == false)
        #expect(await playing(output: true, measured: false, audible: false).plays(42))
    }
}
