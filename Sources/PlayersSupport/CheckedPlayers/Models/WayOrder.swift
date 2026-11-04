import AutoHushKit

/// Which of an added app's kept ways to press, and in which order, with its
/// window in a given state (the user, 2026-11-04): the chosen way, if it
/// worked there; the other ways that show nothing (AppleScript, its page,
/// its menu) that worked there; those not tested there; the Now Playing
/// panel last, where it worked or wasn't tested. A way that failed there is
/// left out; when every way did, the chosen one is pressed, as before
/// backups.
struct WayOrder: Sendable, Equatable {
    /// One kept way, as its check found it.
    struct Way: Sendable, Equatable {
        var kind: CheckResult.WayKind
        /// How it did in the check; `nil` for a setup kept before 2026-11-04.
        var result: CheckResult.WayResult?
    }

    /// The chosen way first, then its backups, in the setup's order.
    let ways: [Way]

    /// The indices of `ways` to press for `target` (`.paused` or
    /// `.playing`) with the window in `state`.
    func order(in state: CheckResult.WindowState, for target: PlayerState) -> [Int] {
        guard !ways.isEmpty else { return [] }
        let found = ways.map { Self.found($0, in: state, for: target) }
        let quiet = ways.indices.filter { ways[$0].kind != .panel }
        var order = found[0] == .worked ? [0] : []
        order += quiet.filter { $0 != 0 && found[$0] == .worked }
        order += quiet.filter { found[$0] == .untested }
        order += ways.indices.filter { ways[$0].kind == .panel && found[$0] != .failed && !order.contains($0) }
        return order.isEmpty ? [0] : order
    }

    /// Whether the order changes with the window's state, so the window has
    /// to be looked at (about 70 ms, up to 1 s) before a press.
    func dependsOnWindow(for target: PlayerState) -> Bool {
        let visible = order(in: .visible, for: target)
        return CheckResult.WindowState.allCases.contains { order(in: $0, for: target) != visible }
    }

    private enum Found { case worked, untested, failed }

    /// A way that only paused the app in its check (`pausedOnly`) worked
    /// there for a pause, not for a play.
    private static func found(_ way: Way, in state: CheckResult.WindowState, for target: PlayerState) -> Found {
        switch way.result?.outcome(in: state) ?? .untested {
        case .worked: .worked
        case .pausedOnly: target == .playing ? .failed : .worked
        case .failed: .failed
        case .untested: .untested
        }
    }
}

extension CheckResult.WayResult {
    /// How it did with the window in `state`, as its check kept it; in a
    /// check saved before 2026-11-04, which kept no states, from its mark
    /// and the states it failed in. `.untested` where it wasn't tried.
    func outcome(in state: CheckResult.WindowState) -> CheckResult.StateResult.Outcome {
        if !states.isEmpty { return states.first { $0.state == state }?.outcome ?? .untested }
        switch mark {
        case .works: return .worked
        case .some: return failedStates.contains(state) ? .failed : .worked
        default: return .untested
        }
    }
}
