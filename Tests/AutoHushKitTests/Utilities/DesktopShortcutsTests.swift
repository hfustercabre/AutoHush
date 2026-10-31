import CoreGraphics
import Testing
@testable import AutoHushKit

@Suite("DesktopShortcuts")
struct DesktopShortcutsTests {
    private func shortcut(enabled: Bool) -> [String: Any] {
        ["enabled": enabled, "value": ["parameters": [65535, 124, 8_650_752], "type": "standard"]]
    }

    @Test("both desktop shortcuts on, or never changed (not listed), are on; either one turned off is off")
    func areOn() {
        #expect(DesktopShortcuts.areOn(in: nil))
        #expect(DesktopShortcuts.areOn(in: [:]))
        #expect(DesktopShortcuts.areOn(in: ["79": shortcut(enabled: true), "81": shortcut(enabled: true)]))
        #expect(DesktopShortcuts.areOn(in: ["32": shortcut(enabled: false)])) // another shortcut off
        #expect(!DesktopShortcuts.areOn(in: ["79": shortcut(enabled: false), "81": shortcut(enabled: true)]))
        #expect(!DesktopShortcuts.areOn(in: ["81": shortcut(enabled: false)]))
    }

    @Test("the check presses each one's keys: Control and the arrow, with Fn, unless the user set others")
    func keys() {
        let standardRight = DesktopShortcuts.Keys(keyCode: 124, flags: [.maskControl, .maskSecondaryFn])
        #expect(DesktopShortcuts.keys(right: true, in: nil) == standardRight)
        #expect(DesktopShortcuts.keys(right: true, in: ["81": ["enabled": true]]) == standardRight) // no keys stored
        #expect(DesktopShortcuts.keys(right: true, in: ["79": shortcut(enabled: true)]) == standardRight) // another one's
        #expect(DesktopShortcuts.keys(right: false, in: ["79": shortcut(enabled: true)]).keyCode == 124) // as stored
        // Control-Option-← and Control-2.
        let left: [String: Any] = ["value": ["parameters": [65535, 123, 0x8C_0000], "type": "standard"]]
        let right: [String: Any] = ["value": ["parameters": [50, 19, 0x4_0000], "type": "standard"]]
        #expect(DesktopShortcuts.keys(right: false, in: ["79": left])
                == DesktopShortcuts.Keys(keyCode: 123, flags: [.maskControl, .maskAlternate, .maskSecondaryFn]))
        #expect(DesktopShortcuts.keys(right: true, in: ["81": right]) == DesktopShortcuts.Keys(keyCode: 19, flags: .maskControl))
        // No key set: as macOS stores a cleared one.
        let cleared: [String: Any] = ["value": ["parameters": [65535, 65535, 0], "type": "standard"]]
        #expect(DesktopShortcuts.keys(right: true, in: ["81": cleared]) == standardRight)
    }
}
