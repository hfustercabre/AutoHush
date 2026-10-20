import AppIntents
import Foundation
import Testing
@testable import AutoHushApp

// `perform()` isn't tested here: App Intents traps when a `@Dependency` is
// read outside a real run. It hands `choice(of:)` to `FocusAutoPause.follow`
// (tested in FocusAutoPauseTests); the live checks run it.
@Suite("AutoPauseFocusFilter")
struct AutoPauseFocusFilterTests {
    /// The filter as a Focus's settings keep it, with `choice`.
    private func filter(_ choice: AutoPauseFocusChoice?) -> AutoPauseFocusFilter {
        let filter = AutoPauseFocusFilter()
        filter.choice = choice
        return filter
    }

    @Test("the filter's choice turns Auto-Pause on or off; none means no Focus with the filter")
    func choiceMapping() {
        #expect(AutoPauseFocusFilter.choice(of: filter(.on)) == true)
        #expect(AutoPauseFocusFilter.choice(of: filter(.off)) == false)
        #expect(AutoPauseFocusFilter.choice(of: filter(nil)) == nil)
        // As macOS makes it at a Focus's end: the choice left unset.
        #expect(AutoPauseFocusFilter.choice(of: AutoPauseFocusFilter()) == nil)
        #expect(AutoPauseFocusChoice.on.isOn)
        #expect(!AutoPauseFocusChoice.off.isOn)
    }

    @Test("the Focus's settings list the filter as 'Auto-Pause On' or 'Auto-Pause Off', its title with no choice")
    func displayRepresentation() {
        #expect(filter(.on).displayRepresentation.title.key == "Auto-Pause On")
        #expect(filter(.off).displayRepresentation.title.key == "Auto-Pause Off")
        #expect(filter(nil).displayRepresentation.title.key == "Auto-Pause")
    }

    @Test("the filter is titled Auto-Pause, with the choices On and Off")
    func choices() {
        #expect(AutoPauseFocusFilter.title.key == "Auto-Pause")
        #expect(AutoPauseFocusChoice.typeDisplayRepresentation.name.key == "Auto-Pause")
        #expect(AutoPauseFocusChoice.allCases == [.on, .off])
        #expect(AutoPauseFocusChoice.caseDisplayRepresentations.count == 2)
        #expect(AutoPauseFocusChoice.caseDisplayRepresentations[.on]?.title.key == "On")
        #expect(AutoPauseFocusChoice.caseDisplayRepresentations[.off]?.title.key == "Off")
    }
}
