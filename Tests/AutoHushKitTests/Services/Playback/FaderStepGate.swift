import Foundation

/// Counts fade steps and can run something at a given step, so tests can
/// interrupt a fade halfway without waiting for real time.
actor FaderStepGate {
    private(set) var steps = 0
    private var actions: [Int: @Sendable () async -> Void] = [:]

    func at(step: Int, _ action: @escaping @Sendable () async -> Void) { actions[step] = action }

    func tick() async {
        steps += 1
        if let action = actions.removeValue(forKey: steps) { await action() }
    }
}
