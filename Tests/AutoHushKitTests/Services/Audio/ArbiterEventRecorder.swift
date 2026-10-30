import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

/// Records every source event delivered to the arbiter.
actor ArbiterEventRecorder: PlaybackArbiting {
    struct Event: Equatable, Sendable {
        let bundleID: String
        let isPlaying: Bool
    }

    private(set) var events: [Event] = []
    /// When each event's app was first heard, as the monitor said, in order.
    private(set) var heardSince: [Date?] = []
    private(set) var playerLocal: [Bool] = []
    /// How long apps take to count, at most, each time the monitor said.
    private(set) var startConfirmations: [TimeInterval] = []
    /// Every call in arrival order, start confirmations aside.
    private(set) var log: [String] = []

    func handleSourceChange(sourceID: String, isPlaying: Bool, heardSince: Date?) async {
        events.append(.init(bundleID: sourceID, isPlaying: isPlaying))
        self.heardSince.append(heardSince)
        log.append("\(isPlaying ? "+" : "-")\(sourceID)")
    }

    func handleLocalPlaybackChange(_ isLocal: Bool) async {
        playerLocal.append(isLocal)
        log.append("playerLocal \(isLocal)")
    }

    func handleStartConfirmationChange(_ longest: TimeInterval) async {
        startConfirmations.append(longest)
    }

    /// How many times the monitor said the player is heard again.
    private(set) var playerHeard = 0

    func handlePlayerHeard() async { playerHeard += 1 }

    func handleCallChange(sourceID: String, inCall: Bool) async {
        log.append("\(inCall ? "call" : "no call") \(sourceID)")
    }

    func waitForPlayerLocal(count: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        await TestWait.until(sourceLocation: sourceLocation) { playerLocal.count >= count }
    }

    func waitForEvents(count: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        await TestWait.until(sourceLocation: sourceLocation) { events.count >= count }
    }
}
