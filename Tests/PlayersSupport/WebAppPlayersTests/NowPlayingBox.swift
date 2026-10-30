import Foundation
import AutoHushKit
@testable import WebAppPlayers
import AutoHushTestSupport

/// The Now Playing app in tests: unknown (the key is pressed, as ever)
/// unless a test sets it. `answers` come one per question, the last one
/// for every question after; `asked` counts the questions.
final class NowPlayingBox: Sendable {
    private let state = Locked((answers: [NowPlayingApp.Answer.unknown], asked: 0))

    var answer: NowPlayingApp.Answer {
        get {
            state.withLock {
                $0.asked += 1
                return $0.answers.count > 1 ? $0.answers.removeFirst() : $0.answers[0]
            }
        }
        set { state.withLock { $0.answers = [newValue] } }
    }
    var answers: [NowPlayingApp.Answer] {
        get { state.value.answers }
        set { state.withLock { $0.answers = newValue } }
    }
    var asked: Int { state.value.asked }
}
