import Foundation
@testable import AutoHushApp

/// Stands in for a player's monitoring kept by `HeldPauses`.
@MainActor
final class FakeMonitoring: HeldMonitoring {
    private(set) var stops = 0
    private(set) var restoredStops = 0
    private(set) var autoPause: Bool?
    private(set) var ignored: Set<String>?

    func stop() { stops += 1 }
    func stopAndRestoreVolume() async { restoredStops += 1 }
    func setAutoPauseEnabled(_ enabled: Bool) { autoPause = enabled }
    func setIgnoredSources(_ ids: Set<String>) { ignored = ids }
}
