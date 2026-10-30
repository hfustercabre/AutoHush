import Foundation
import AutoHushKit
@testable import AutoHushApp

/// Makes the player session's monitorings as `FakeMonitoring`s, and keeps
/// them in the order made.
@MainActor
final class FakeMonitorings {
    private(set) var made: [FakeMonitoring] = []
    /// Whether the monitorings made from now on find the pause they're asked
    /// to take over.
    var findPauses = false

    /// The monitorings made for `bundleID`.
    func of(_ bundleID: String) -> [FakeMonitoring] { made.filter { $0.bundleID == bundleID } }

    var make: PlayerSession.MakeMonitoring {
        { [self] player, setup, onUpdate in
            let monitoring = FakeMonitoring(bundleID: player.bundleID, setup: setup, findsPause: findPauses, onUpdate: onUpdate)
            made.append(monitoring)
            return monitoring
        }
    }
}
