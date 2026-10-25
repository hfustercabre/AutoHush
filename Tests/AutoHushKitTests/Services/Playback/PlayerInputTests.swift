import CoreGraphics
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

    /// How long ago each kind of input came, as macOS would say; never for the rest.
    private func ago(_ times: [CGEventType: Double]) -> (CGEventType) -> Double {
        { times[$0] ?? .infinity }
    }

    @Test("a media key is the last system-defined event, unless a mouse button's came at that moment")
    func mediaKeys() {
        let now = front, key = UserInput.systemDefined
        #expect(UserInput.lastMediaKey(now: now, secondsSince: ago([key: 2])) == now.addingTimeInterval(-2))
        #expect(UserInput.lastMediaKey(now: now, secondsSince: ago([key: 2, .leftMouseUp: 2.02])) == nil) // the button's
        #expect(UserInput.lastMediaKey(now: now, secondsSince: ago([key: 2, .leftMouseUp: 2.2])) != nil)
        #expect(UserInput.lastMediaKey(now: now, secondsSince: ago([key: 2, .keyDown: 1])) != nil) // a key after it
        #expect(UserInput.lastMediaKey(now: now, secondsSince: ago([:])) == nil)
    }

    @Test("a click in the player stays the user's though a key is pressed in another app after it; input before the moment doesn't count")
    func eachKindRead() {
        let now = front.addingTimeInterval(20)
        let spans: [PlayerInput.FrontSpan] = [(front, now.addingTimeInterval(-1))] // in front until a second ago
        let input = ago([.leftMouseDown: 2, .keyDown: 0.5])
        #expect(PlayerInput.played(since: now.addingTimeInterval(-3), now: now, spans: spans, secondsSince: input))
        #expect(!PlayerInput.played(since: now.addingTimeInterval(-1.5), now: now, spans: spans, secondsSince: input))
        #expect(!PlayerInput.played(since: now.addingTimeInterval(-3), now: now, spans: [], secondsSince: input)) // never in front
        #expect(PlayerInput.played(since: now.addingTimeInterval(-3), now: now, spans: [],
                                   secondsSince: ago([UserInput.systemDefined: 1]))) // a media key, wherever
    }

    @Test("the player coming forward opens a span, another app closes it, and spans ended over 10 minutes ago are forgotten")
    func spansFollowActivations() {
        var spans = PlayerInput.spans([], afterActivating: "org.videolan.vlc", player: "org.videolan.vlc", at: front)
        spans = PlayerInput.spans(spans, afterActivating: "org.videolan.vlc", player: "org.videolan.vlc", at: front.addingTimeInterval(1))
        #expect(spans.count == 1) // still the open one
        spans = PlayerInput.spans(spans, afterActivating: "com.apple.Safari", player: "org.videolan.vlc", at: front.addingTimeInterval(5))
        #expect(spans.first?.to == front.addingTimeInterval(5))
        spans = PlayerInput.spans(spans, afterActivating: "com.apple.Safari", player: "org.videolan.vlc",
                                  at: front.addingTimeInterval(5 + PlayerInput.spanMemory + 1))
        #expect(spans.isEmpty)
    }
}
