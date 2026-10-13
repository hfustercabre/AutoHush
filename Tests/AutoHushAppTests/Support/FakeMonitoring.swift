import Foundation
import AutoHushKit
@testable import AutoHushApp

/// Stands in for a player's monitoring, as the player session runs it and
/// `HeldPauses` keeps it. What it's told is recorded; `send` passes on an
/// update as the engine would.
@MainActor
final class FakeMonitoring: SessionMonitoring {
    /// The player it monitors, and what it started with (when the session made it).
    let bundleID: String?
    let setup: PlayerSession.MonitoringSetup?
    private let onUpdate: (@MainActor (MonitoringPipeline.StatusUpdate) -> Void)?
    /// Whether `start` finds the pause it's asked to take over.
    private let findsPause: Bool

    private(set) var starts: [(takingOverPause: Bool, asleep: Bool)] = []
    private(set) var stops = 0
    private(set) var restoredStops = 0
    private(set) var autoPause: Bool?
    private(set) var ignored: Set<String>?
    private(set) var asleep: [Bool] = []
    private(set) var configurations: [AppConfiguration] = []
    private(set) var detectionMethods: [DetectionMethod] = []

    init(bundleID: String? = nil, setup: PlayerSession.MonitoringSetup? = nil, findsPause: Bool = false,
         onUpdate: (@MainActor (MonitoringPipeline.StatusUpdate) -> Void)? = nil) {
        self.bundleID = bundleID
        self.setup = setup
        self.findsPause = findsPause
        self.onUpdate = onUpdate
    }

    var isStopped: Bool { stops + restoredStops > 0 }

    func start(takingOverPause: Bool, asleep: Bool) async -> Bool {
        starts.append((takingOverPause, asleep))
        return takingOverPause && findsPause
    }

    func send(_ update: MonitoringPipeline.StatusUpdate) { onUpdate?(update) }

    func stop() { stops += 1 }
    func stopAndRestoreVolume() async { restoredStops += 1 }
    func setAutoPauseEnabled(_ enabled: Bool) { autoPause = enabled }
    func setIgnoredSources(_ ids: Set<String>) { ignored = ids }
    func setAsleep(_ asleep: Bool) { self.asleep.append(asleep) }
    func setConfiguration(_ configuration: AppConfiguration) { configurations.append(configuration) }
    func setDetectionMethod(_ method: DetectionMethod) { detectionMethods.append(method) }
    func activeAudioReport() -> [ActiveAudioReport.Entry] { [] }
}

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
