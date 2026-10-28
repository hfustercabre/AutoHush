import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import AutoHushKit

@Suite("PlayerWindowClicks")
struct PlayerWindowClicksTests {
    /// A window as `CGWindowListCopyWindowInfo` lists it.
    /// Layers: 0 ordinary windows, 25 the menu bar's icons, 101 menus.
    static func window(_ frame: CGRect, owner: pid_t, layer: Int = 0, alpha: Double = 1) -> [String: Any] {
        [kCGWindowBounds as String: frame.dictionaryRepresentation as NSDictionary,
         kCGWindowOwnerPID as String: NSNumber(value: owner), kCGWindowLayer as String: NSNumber(value: layer),
         kCGWindowAlpha as String: alpha]
    }

    @Test("a click lands in the frontmost window under it that can be seen")
    func clickOwner() {
        let menu = Self.window(CGRect(x: 1000, y: 24, width: 200, height: 120), owner: 42, layer: 101)
        let icon = Self.window(CGRect(x: 1100, y: 0, width: 24, height: 24), owner: 42, layer: 25)
        let clear = Self.window(CGRect(x: 0, y: 0, width: 2000, height: 2000), owner: 7, alpha: 0)
        let browser = Self.window(CGRect(x: 0, y: 0, width: 1600, height: 1000), owner: 99)
        let windows = [clear, menu, icon, browser]
        #expect(PlayerWindowClicks.window(at: CGPoint(x: 1050, y: 60), in: windows).map { "\($0.owner) \($0.layer)" } == "42 101") // its menu, over the browser
        #expect(PlayerWindowClicks.window(at: CGPoint(x: 1110, y: 10), in: windows).map { "\($0.owner) \($0.layer)" } == "42 25") // its menu bar icon
        #expect(PlayerWindowClicks.window(at: CGPoint(x: 300, y: 300), in: windows).map { "\($0.owner) \($0.layer)" } == "99 0")
        #expect(PlayerWindowClicks.window(at: CGPoint(x: 1900, y: 1500), in: windows) == nil) // only the clear one
    }

    @Test("a click is kept only in the player's windows above ordinary ones")
    func takesItsIconAndMenuOnly() {
        let clicks = PlayerWindowClicks(memory: PlayerInput.spanMemory) { $0 == 42 }
        let windows = [Self.window(CGRect(x: 1100, y: 0, width: 24, height: 24), owner: 42, layer: 25),
                       Self.window(CGRect(x: 1200, y: 100, width: 300, height: 300), owner: 42)]
        let start = Date()
        clicks.take(at: CGPoint(x: 1300, y: 200), windows: windows, date: start) // its ordinary window
        #expect(!clicks.since(start.addingTimeInterval(-1)))
        clicks.take(at: CGPoint(x: 1110, y: 10), windows: windows, date: start) // its menu bar icon
        #expect(clicks.since(start.addingTimeInterval(-1)))
        #expect(!clicks.since(start))
    }
}
