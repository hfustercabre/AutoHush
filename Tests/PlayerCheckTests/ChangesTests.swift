import Foundation
import Testing
@testable import PlayerCheck

/// What the check changed, which a stop on another thread puts back.
@Suite("playercheck: what it changed")
struct ChangesTests {
    @Test("a switch is noted once, and each change is made whole: a stop takes them all and leaves none")
    func switches() {
        let changes = Changes()
        changes.noteOn("AXManualAccessibility")
        changes.noteOn("AXEnhancedUserInterface")
        changes.noteOn("AXManualAccessibility")
        #expect(changes.switchesOn == ["AXManualAccessibility", "AXEnhancedUserInterface"])
        changes.noteOff("AXManualAccessibility")
        #expect(changes.switchesOn == ["AXEnhancedUserInterface"])
        #expect(changes.takeSwitchesOn() == ["AXEnhancedUserInterface"])
        #expect(changes.switchesOn.isEmpty)
    }

    @Test("switches noted from many threads at once are all kept, each once")
    func atOnce() async {
        let changes = Changes()
        let names = (0..<200).map { "switch \($0)" }
        await withTaskGroup(of: Void.self) { group in
            for name in names {
                group.addTask {
                    changes.noteOn(name)
                    changes.noteOn(name)
                }
            }
        }
        #expect(Set(changes.switchesOn) == Set(names))
        #expect(changes.switchesOn.count == names.count)
    }
}
