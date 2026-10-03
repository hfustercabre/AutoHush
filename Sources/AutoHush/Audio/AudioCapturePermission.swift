import Foundation

/// State of the System Audio Recording privacy permission (TCC service
/// `kTCCServiceAudioCapture`), which CoreAudio process taps require.
enum AudioCapturePermission: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
}

protocol AudioCapturePermissionChecking: Sendable {
    /// The current state, or `nil` when it cannot be determined.
    func status() -> AudioCapturePermission?
    /// Shows the system prompt if the user has not decided yet.
    func request(completion: @escaping @Sendable (Bool) -> Void)
}

/// Reads and requests the permission through TCC.
///
/// macOS offers no public API for this permission, and process taps simply
/// deliver silence when it is missing. `TCCAccessPreflight` and
/// `TCCAccessRequest` are private TCC functions (also used by Apple's own
/// tools and by AudioCap); they are resolved at runtime, so if a future macOS
/// removes them `status()` returns `nil` and AudioMonitor falls back to
/// inferring the permission from tapped samples.
struct TCCAudioCapturePermission: AudioCapturePermissionChecking {
    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias RequestFunction = @convention(c) (
        CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void
    ) -> Void

    private struct Functions: @unchecked Sendable {
        let preflight: PreflightFunction
        let request: RequestFunction
    }

    private static let service = "kTCCServiceAudioCapture"

    private static let functions: Functions? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
              let preflight = dlsym(handle, "TCCAccessPreflight"),
              let request = dlsym(handle, "TCCAccessRequest")
        else { return nil }
        return Functions(
            preflight: unsafeBitCast(preflight, to: PreflightFunction.self),
            request: unsafeBitCast(request, to: RequestFunction.self)
        )
    }()

    func status() -> AudioCapturePermission? {
        guard let functions = Self.functions else { return nil }
        switch functions.preflight(Self.service as CFString, nil) {
        case 0:  return .granted
        case 1:  return .denied
        case 2:  return .notDetermined
        default: return nil
        }
    }

    func request(completion: @escaping @Sendable (Bool) -> Void) {
        guard let functions = Self.functions else { return completion(false) }
        functions.request(Self.service as CFString, nil) { granted in completion(granted) }
    }
}
