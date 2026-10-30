import Foundation
import AutoHushTestSupport

/// Counts a fade's steps (each sleep before a volume change) and holds it
/// at the ones given until let go, so a test acts mid-fade, however busy the
/// machine.
actor FadeSteps {
    private(set) var count = 0
    private var holds: [Int: Gate] = [:]

    init(holdingAt steps: Int...) {
        for step in steps { holds[step] = Gate() }
    }

    func step() async {
        count += 1
        await holds[count]?.wait()
    }

    func letGo(_ step: Int) async { await holds[step]?.open() }
}
