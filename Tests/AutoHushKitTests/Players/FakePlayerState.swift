import Foundation
@testable import AutoHushKit
import AutoHushTestSupport

/// A player state the test changes, counting how often it was read.
final class FakePlayerState: Sendable {
    private let box: Locked<(state: PlayerState, reads: Int)>

    init(_ state: PlayerState) { box = Locked((state, 0)) }

    var state: PlayerState {
        get { box.value.state }
        set { box.withLock { $0.state = newValue } }
    }
    var reads: Int { box.value.reads }

    func read() -> PlayerState {
        box.withLock {
            $0.reads += 1
            return $0.state
        }
    }
}
