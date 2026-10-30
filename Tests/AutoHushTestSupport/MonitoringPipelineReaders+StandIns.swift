import Foundation
import AutoHushKit

// Stand-ins for what AudioMonitor reads from macOS: the audio processes, their
// levels, the power assertions and the System Audio Recording permission.
// Shared by the engine's tests and the app's (the player session's pipelines).

extension MonitoringPipeline.Readers {
    /// Stand-ins for all the pipeline reads from macOS, Audio Recording
    /// allowed and every start of the player the user's.
    package static func standIns(
        processes: MockAudioProcessSnapshotProvider = MockAudioProcessSnapshotProvider(),
        levelMeter: MockLevelMeter = MockLevelMeter(),
        powerAssertions: MockPowerAssertions = MockPowerAssertions(),
        outputDisconnects: MockOutputDisconnects = MockOutputDisconnects(),
        playerMute: @escaping @Sendable (String, @escaping @Sendable () -> Bool) -> (any PlayerMuting)? = {
            ProcessPlayerMute(bundleID: $0, tapsAllowed: $1)
        }
    ) -> Self {
        Self(processes: processes, levelMeter: levelMeter, audioCapturePermission: MockAudioCapturePermission(.granted),
             powerAssertions: powerAssertions, outputDisconnects: outputDisconnects, playerMute: playerMute,
             playerInput: { _ in { _ in true } })
    }
}
