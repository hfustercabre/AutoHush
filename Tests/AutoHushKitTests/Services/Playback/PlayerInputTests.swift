import Foundation
import Testing
@testable import AutoHushKit

@Suite("PlayerInput")
struct PlayerInputTests {
    private let front = Date(timeIntervalSinceReferenceDate: 1000)

    @Test("input while the player is already in front counts; the click or keys that bring it forward don't")
    func onlyInputInFront() {
        let spans: [PlayerInput.FrontSpan] = [(front, nil)]
        #expect(PlayerInput.inFront(at: front.addingTimeInterval(1), spans: spans))
        #expect(!PlayerInput.inFront(at: front.addingTimeInterval(-0.1), spans: spans)) // the click that brought it forward
    }

    @Test("a click that brings another app forward, a moment before macOS says so, is that app's")
    func clickAwayIsTheOtherApps() {
        let away = front.addingTimeInterval(10)
        let spans: [PlayerInput.FrontSpan] = [(front, away)]
        #expect(PlayerInput.inFront(at: away.addingTimeInterval(-PlayerInput.activationLag - 0.1), spans: spans))
        #expect(!PlayerInput.inFront(at: away.addingTimeInterval(-0.1), spans: spans))
        #expect(!PlayerInput.inFront(at: away.addingTimeInterval(1), spans: spans))
    }
}
