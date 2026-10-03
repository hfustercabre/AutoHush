import Foundation

/// The undocumented TCC (privacy database) functions `TCCAccessPreflight` and
/// `TCCAccessRequest`, from the private TCC framework.
///
/// macOS has no public API for some permissions (System Audio Recording among
/// them). These functions are also used by Apple's own tools and by AudioCap.
/// They are resolved at runtime, so if a macOS update removes them the calls
/// report "unavailable" instead of crashing, and callers fall back.
///
/// Check after every major macOS release.
enum TCC {
    /// What `TCCAccessPreflight` answers.
    enum Preflight: Int32 {
        case granted = 0
        case denied = 1
        case notDetermined = 2
    }

    /// The service's current state, or `nil` when TCC can't be asked.
    static func preflight(_ service: String) -> Preflight? {
        guard let functions else { return nil }
        return Preflight(rawValue: functions.preflight(service as CFString, nil))
    }

    /// Shows the system prompt if the user hasn't decided yet. Returns `false`,
    /// without calling `completion`, when TCC can't be asked.
    static func request(_ service: String, completion: @escaping @Sendable (Bool) -> Void) -> Bool {
        guard let functions else { return false }
        functions.request(service as CFString, nil) { granted in completion(granted) }
        return true
    }

    // MARK: - Resolution

    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias RequestFunction = @convention(c) (
        CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void
    ) -> Void

    private struct Functions: @unchecked Sendable {
        let preflight: PreflightFunction
        let request: RequestFunction
    }

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
}
