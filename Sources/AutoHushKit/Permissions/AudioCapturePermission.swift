import Foundation

/// State of the System Audio Recording privacy permission (TCC service
/// `kTCCServiceAudioCapture`), which CoreAudio process taps require.
package enum AudioCapturePermission: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
}

/// Reads and requests the System Audio Recording permission.
package protocol AudioCapturePermissionChecking: Sendable {
    /// The current state, or `nil` when it cannot be determined.
    func status() -> AudioCapturePermission?
    /// Shows the system prompt if the user has not decided yet.
    func request(completion: @escaping @Sendable (Bool) -> Void)
}

/// Reads and requests the permission through TCC (see `TCC` in PrivateAPI).
///
/// macOS offers no public API for this permission, and process taps simply
/// deliver silence when it is missing. If TCC can't be asked, `status()`
/// returns `nil` and AudioMonitor falls back to inferring the permission from
/// tapped samples.
package struct TCCAudioCapturePermission: AudioCapturePermissionChecking {
    package init() {}

    private static let service = "kTCCServiceAudioCapture"

    package func status() -> AudioCapturePermission? {
        switch TCC.preflight(Self.service) {
        case .granted?:       return .granted
        case .denied?:        return .denied
        case .notDetermined?: return .notDetermined
        case nil:             return nil
        }
    }

    package func request(completion: @escaping @Sendable (Bool) -> Void) {
        if !TCC.request(Self.service, completion: completion) { completion(false) }
    }
}
