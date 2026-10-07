import Darwin

/// The undocumented libsystem function `responsibility_get_pid_responsible_for_pid`:
/// the process macOS holds responsible for another one (the app behind a
/// helper or XPC service, such as WebKit's audio process for Safari).
///
/// Resolved at runtime; if a macOS update removes it, `responsiblePID(for:)`
/// returns `nil` and callers fall back to the executable's path.
///
/// Check after every major macOS release.
package enum ProcessResponsibility {
    /// The responsible process, or `nil` when unknown or the function is unavailable.
    package static func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let function, case let owner = function(pid), owner > 0 else { return nil }
        return owner
    }

    /// Whether `pid` is the app running as `appPID`, or one of its helpers
    /// (a web app's sound comes from its WebKit process).
    package static func isOwned(_ pid: pid_t, by appPID: pid_t) -> Bool {
        pid == appPID || responsiblePID(for: pid) == appPID
    }

    private typealias Function = @convention(c) (pid_t) -> pid_t

    private static let function: Function? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: Function.self)
    }()
}
