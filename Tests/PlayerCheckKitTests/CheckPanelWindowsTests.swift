import CoreGraphics
import Foundation
import Testing
@testable import PlayerCheckKit

@Suite("CheckPanelWindows")
struct CheckPanelWindowsTests {
    private func window(_ pid: pid_t, layer: Int, _ frame: CGRect) -> [String: Any] {
        [kCGWindowOwnerPID as String: Int(pid), kCGWindowLayer as String: layer,
         kCGWindowBounds as String: frame.dictionaryRepresentation as NSDictionary]
    }

    @Test("only the panel's windows let clicks through: not the menu bar icon, its menu, the shade, or another app's")
    func panel() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = CGRect(x: 1100, y: 40, width: 300, height: 200), raised = CGRect(x: 1100, y: 40, width: 300, height: 210)
        let windows = [
            window(10, layer: 3, panel),                              // the panel, floating
            window(10, layer: 103, raised),                           // the panel while the screen is dimmed
            window(10, layer: 25, CGRect(x: 1200, y: 0, width: 30, height: 24)),  // its menu bar icon
            window(10, layer: 101, CGRect(x: 1180, y: 24, width: 220, height: 300)), // its menu
            window(10, layer: 102, screen),                           // the shade
            window(10, layer: 0, CGRect(x: 0, y: 0, width: 600, height: 400)),     // an ordinary window
            window(11, layer: 3, CGRect(x: 0, y: 0, width: 100, height: 100)),     // another app's floating window
        ]
        #expect(CheckPanelWindows.frames(in: windows, ownedBy: 10, screens: [screen]) == [panel, raised])
    }
}
