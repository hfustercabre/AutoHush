import CheckedPlayers
import Testing
@testable import PlayerCheckKit

@Suite("WindowState+OutOfView")
struct WindowStateOutOfViewTests {
    @Test("only the states on another desktop need Mission Control's desktop shortcuts")
    func needsDesktopShortcuts() {
        let needing = CheckResult.WindowState.allCases.filter(\.needsDesktopShortcuts)
        #expect(needing == [.otherDesktop, .otherDesktopCovered])
    }
}
