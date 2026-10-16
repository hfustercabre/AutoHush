import Foundation
import CheckedPlayers

/// How a check ended.
enum PlayerCheckEnd: Equatable {
    /// Why a check couldn't finish, as far as AutoHush can tell.
    enum Reason: Equatable {
        /// The app quit (or crashed) during the check.
        case appQuit
        /// The app is no longer where it was checked.
        case appNotFound
        /// Anything else: the check's log says why.
        case other
    }

    /// It went through: what it found (`nil` if it wrote nothing).
    case finished(CheckResult?)
    /// Stopped (Stop, Escape, or its window closed): what it changed is put back.
    case stopped
    /// It didn't start: a permission it needs is missing (it checks them
    /// all before doing anything).
    case permissionMissing
    /// It ended otherwise, with this exit status.
    case failed(Int32)

    /// How the helper's exit `status` ends a check: `stopped` when AutoHush
    /// asked it to stop; the result file's contents for a check that went
    /// through.
    static func of(status: Int32, stopped: Bool, result: Data?) -> PlayerCheckEnd {
        switch status {
        case 0: .finished(result.flatMap { try? JSONDecoder().decode(CheckResult.self, from: $0) })
        case 3: .permissionMissing
        default: stopped || status == 143 || status == 130 ? .stopped : .failed(status)
        }
    }
}
