import Foundation
import Testing
@testable import PlayerCheck

/// Where the tool's log and caches go while it's tested, removed at the end.
let testRunFolder = FileManager.default.temporaryDirectory.appending(path: "PlayerCheckTests-\(UUID().uuidString)").path

/// The tool as the tests run it: a read-only check of Calculator, with its
/// own folders. Set once, before anything reads its command line.
private let commandLineSet: Void = {
    argumentsForTests = ["/System/Applications/Calculator.app", "--read-only", "--logs", testRunFolder, "--caches", testRunFolder]
    atexit { _ = try? FileManager.default.removeItem(atPath: testRunFolder) }
}()

/// The tool's command line set for its tests. The tool reads it once, at
/// its first use (`arguments`), and the test runner's own names no app,
/// which ends the tool (`target`) and the whole test run with it. So every
/// suite of this target takes this trait: Swift Testing makes each suite's
/// traits as it finds the tests, before it picks those to run, and prepares
/// them before any test starts. Either sets the command line, so no test of
/// any suite reads it first, whichever runs.
struct ReadOnlyRun: SuiteTrait {
    init() { _ = commandLineSet }

    func prepare(for test: Testing.Test) async throws { _ = commandLineSet }
}

extension Trait where Self == ReadOnlyRun {
    /// The tool's command line set for its tests (`ReadOnlyRun`).
    static var readOnlyRun: Self { Self() }
}
