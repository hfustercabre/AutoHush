import CoreAudio
import Foundation

// AudioMonitor: the System Audio Recording permission, and the detection
// mode it gives.
extension AudioMonitor {
    /// Re-reads the System Audio Recording permission (at most every few
    /// seconds) and derives the detection mode from it when it is known.
    /// It never asks macOS itself: an undecided permission counts as
    /// missing until the user's Allow… asks (P1, the user's pick,
    /// 2026-11-06: macOS's prompt at launch came over the welcome window's
    /// Allow…); a grant is read here within `permissionRecheckInterval`.
    func checkPermission(at now: Date) {
        guard detectionMethod == .audioLevels else {
            setDetectionMode(detectionMethod == .playbackSignals ? .playbackSignals : .disabled)
            return
        }
        guard let permission else { return }
        if let lastPermissionCheck,
           now.timeIntervalSince(lastPermissionCheck) < Self.permissionRecheckInterval { return }
        lastPermissionCheck = now

        let status = permission.status()
        let changed = status != permissionStatus
        permissionStatus = status
        switch status {
        case .granted:
            setDetectionMode(.audioLevel)
        case .denied, .notDetermined:
            setDetectionMode(.unavailable)
        case nil:
            break
        }
        if changed {
            let said = switch status {
            case .granted: "allowed"
            case .denied: "denied"
            case .notDetermined: "not asked yet"
            case nil: "unknown"
            }
            logger.info("[monitor] System Audio Recording permission: \(said, privacy: .public)")
            updateMeteredProcesses(at: now)
        }
    }

    /// Infers the permission from samples; only used when TCC cannot be read.
    func updateDetectionMode(peaks: [AudioObjectID: Float], at now: Date) {
        guard permissionStatus == nil else { return }
        if detectionMode != .audioLevel, peaks.values.contains(where: { $0 > 0 }) {
            setDetectionMode(.audioLevel)
            updateMeteredProcesses(at: now) // verification taps on the player are no longer needed
        } else if detectionMode == .pending,
                  let playingSince = playerPlayingSince,
                  let tapSince = playerTapSince,
                  now.timeIntervalSince(max(playingSince, tapSince)) >= Self.verificationWindow {
            setDetectionMode(.unavailable)
        }
    }

    func setDetectionMode(_ mode: DetectionMode) {
        guard mode != detectionMode else { return }
        detectionMode = mode
        logger.info("[monitor] detection: \(String(describing: mode), privacy: .public)")
        onDetectionModeChange(mode)
    }
}
