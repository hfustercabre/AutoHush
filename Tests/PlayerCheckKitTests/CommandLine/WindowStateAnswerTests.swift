import Foundation
import Testing
@testable import PlayerCheckKit
import CheckedPlayers

/// The window state answer as the helper writes it is read back the same.
@Suite("WindowStateAnswer")
struct WindowStateAnswerTests {
    @Test("the window's state: each one by its title, no window, not running; no app is none of them")
    func windowState() {
        let answers = CheckResult.WindowState.allCases.map(WindowStateAnswer.state) + [.noWindow, .notRunning]
        for answer in answers {
            #expect(WindowStateAnswer(line: answer.line + "\n") == answer)
        }
        #expect(WindowStateAnswer.state(.covered).windowState == .covered && WindowStateAnswer.noWindow.windowState == nil)
        #expect(WindowStateAnswer(line: CommandLineOptions.AppQuery.noApp) == nil)
    }
}
