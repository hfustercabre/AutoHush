import Foundation
import Testing
@testable import PlayerCheckKit

/// The launch option answer as the helper writes it is read back the same.
@Suite("LaunchOptionAnswer")
struct LaunchOptionAnswerTests {
    @Test("the launch option: the one it needs and whether it runs with it, or none needed")
    func launchOption() {
        for running in [LaunchOptionAnswer.Running.yes, .no, .notRunning] {
            let answer = LaunchOptionAnswer(option: "--disable-backgrounding-occluded-windows", running: running)
            #expect(LaunchOptionAnswer(line: answer.line + "\n") == answer)
        }
        let none = LaunchOptionAnswer(option: nil, running: nil)
        #expect(none.line == "\t" && LaunchOptionAnswer(line: none.line) == none)
        #expect(LaunchOptionAnswer(line: CommandLineOptions.AppQuery.noApp) == nil)
    }
}
