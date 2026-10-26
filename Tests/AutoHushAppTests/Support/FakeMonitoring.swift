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
    private(set) var resumesHeld: [Bool] = []
    private(set) var configurations: [AppConfiguration] = []
    private(set) var detectionMethods: [DetectionMethod] = []
    /// A resume under way (its player fading back in), from `beginResume()`
    /// to `endResume()`: `waitForResume` waits for it.
    private var resumeWaiters: [CheckedContinuation<Void, Never>]?
    /// How many waits for a resume are over.
    private(set) var resumeWaitsOver = 0
    /// The apps with sound it reports, as Diagnostics lists them.
    var audioReport: [ActiveAudioReport.Entry] = []

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

    func beginResume() { resumeWaiters = [] }

    func endResume() {
        resumeWaiters?.forEach { $0.resume() }
        resumeWaiters = nil
    }

    /// Something waits for the resume under way to end.
    var isWaitingForResume: Bool { resumeWaiters?.isEmpty == false }

    func waitForResume() async {
        if resumeWaiters != nil { await withCheckedContinuation { resumeWaiters?.append($0) } }
        resumeWaitsOver += 1
    }

    func stop() { stops += 1 }
    func stopAndRestoreVolume() async { restoredStops += 1 }
    func setAutoPauseEnabled(_ enabled: Bool) { autoPause = enabled }
    func setIgnoredSources(_ ids: Set<String>) { ignored = ids }
    func setAsleep(_ asleep: Bool) { self.asleep.append(asleep) }
    func holdResumes(_ held: Bool) { resumesHeld.append(held) }
    private(set) var resumeRetries = 0
    func retryResume() { resumeRetries += 1 }
    private(set) var unmutesInstead = 0
    func unmuteInstead() { unmutesInstead += 1 }
    func setConfiguration(_ configuration: AppConfiguration) { configurations.append(configuration) }
    func setDetectionMethod(_ method: DetectionMethod) { detectionMethods.append(method) }
    func activeAudioReport() -> [ActiveAudioReport.Entry] { audioReport }
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
