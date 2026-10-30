import Foundation

/// How playercheck ends, as its exit status tells whoever ran it.
package enum CheckExitStatus {
    /// It went through (a check, a press, an answer).
    package static let done: Int32 = 0
    /// It couldn't (no such app, a press that didn't take…): its output says why.
    package static let failed: Int32 = 1
    /// A test didn't start: a permission it needs is missing, or the app
    /// didn't answer whether it may be scripted. Nothing was moved or pressed.
    package static let permissionMissing: Int32 = 3
    /// Stopped by `signal` (Ctrl-C, Stop, Escape while input is blocked, or
    /// whoever ran it gone), after putting back what it changed.
    package static func stopped(by signal: Int32) -> Int32 { 128 + signal }
    /// Stopped as by Stop (SIGTERM): what a check that stops itself ends with.
    package static let stop: Int32 = 128 + SIGTERM

    /// Whether `status` is a stop's.
    package static func isStop(_ status: Int32) -> Bool {
        status == stopped(by: SIGTERM) || status == stopped(by: SIGINT)
    }
}
