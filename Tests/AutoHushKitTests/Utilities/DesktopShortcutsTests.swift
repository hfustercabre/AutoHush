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
}
