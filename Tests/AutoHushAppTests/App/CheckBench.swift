import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

/// Add an App's check on the stand-ins, its app ready to check
/// (`AppDelegateTests.readyToCheck`).
@MainActor
struct CheckBench {
    let scratch: AppDelegateTests.Scratch
    let world: World
    let sut: AppDelegate
    let model: AddAppModel

    /// Whether the Mac's output is muted.
    var muted: Bool { scratch.outputs.mutes[7] == true }

    /// Starts a check and waits until it runs.
    func check() async {
        world.run = FakeCheckRun()
        let runs = world.runs
        model.startCheck()
        await TestWait.until { world.runs == runs + 1 }
    }
}
