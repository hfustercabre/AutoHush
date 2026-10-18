import Foundation
import os
import Testing
@testable import WebAppPlayers

@Suite("SharedSwitches")
struct SharedSwitchesTests {
    /// A process's switch for assistive tools, as a page sets it.
    final class Switch: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: (on: false, turnedOn: 0))
        var isOn: Bool { state.withLock { $0.on } }
        var timesTurnedOn: Int { state.withLock { $0.turnedOn } }
        func turnOn() { state.withLock { $0 = (true, $0.turnedOn + 1) } }
        func turnOff() { state.withLock { $0.on = false } }
    }

    /// `page`'s look at the switch on process 42.
    private func look(_ switches: SharedSwitches, _ light: Switch, by page: UUID, attribute: String = PageAccess.electronSwitch) {
        switches.use(attribute, on: 42, by: page, readsBack: attribute == PageAccess.voiceOverSwitch,
                     isOn: { light.isOn }, turnOn: light.turnOn)
    }

    @Test("the first page's look turns the switch on, the last page released turns it off; one found on stays on")
    func shared() {
        let switches = SharedSwitches(startTime: { _ in 1 })
        let light = Switch()
        let (first, second) = (UUID(), UUID())
        look(switches, light, by: first)
        look(switches, light, by: second)
        #expect(light.isOn && light.timesTurnedOn == 1)
        switches.release(first) { _ in light.turnOff() }
        #expect(light.isOn)
        switches.release(second) { _ in light.turnOff() }
        #expect(!light.isOn)

        // On already (another tool's): left on.
        light.turnOn()
        look(switches, light, by: first)
        switches.release(first) { _ in light.turnOff() }
        #expect(light.isOn)
    }

    @Test("a look while the last page releases the switch waits for it to go off, then turns it on: it's never left off")
    func lookWhileReleasing() {
        let switches = SharedSwitches(startTime: { _ in 1 })
        let light = Switch()
        let (old, new) = (UUID(), UUID())
        let electron = PageAccess.electronSwitch
        look(switches, light, by: old)
        let looked = DispatchSemaphore(value: 0)
        switches.release(old) { _ in
            // The new page looks meanwhile (an app checked again, its old
            // player released): it mustn't take the switch going off as on.
            Thread.detachNewThread {
                switches.use(electron, on: 42, by: new, readsBack: false, isOn: { light.isOn }, turnOn: light.turnOn)
                looked.signal()
            }
            #expect(looked.wait(timeout: .now() + 0.3) == .timedOut)
            light.turnOff()
        }
        looked.wait()
        #expect(light.isOn && light.timesTurnedOn == 2)
        // The new page's to turn off.
        switches.release(new) { _ in light.turnOff() }
        #expect(!light.isOn)
    }

    @Test("a switch on a process that quit isn't turned off on the one that has its pid now, whose own look turns its own on")
    func reusedPID() {
        let started = OSAllocatedUnfairLock(initialState: UInt64(1))
        let switches = SharedSwitches(startTime: { _ in started.withLock { $0 } })
        let (quit, now) = (Switch(), Switch())
        let (first, second) = (UUID(), UUID())
        look(switches, quit, by: first)
        started.withLock { $0 = 2 } // pid 42 is another process's
        look(switches, now, by: second)
        #expect(now.isOn)
        var turnedOff: [SharedSwitches.Key] = []
        switches.release(first) { turnedOff.append($0) }
        #expect(turnedOff.isEmpty)
        switches.release(second) { turnedOff.append($0) }
        #expect(turnedOff.map(\.started) == [2])
    }

    @Test("VoiceOver's switch, read back at each look, is turned on again after another tool turned it off")
    func readBack() {
        let switches = SharedSwitches(startTime: { _ in 1 })
        let light = Switch()
        let page = UUID()
        look(switches, light, by: page, attribute: PageAccess.voiceOverSwitch)
        light.turnOff() // a check of another web app of the browser, at its end
        look(switches, light, by: page, attribute: PageAccess.voiceOverSwitch)
        #expect(light.isOn && light.timesTurnedOn == 2)
        var turnedOff = 0
        switches.release(page) { _ in turnedOff += 1 }
        #expect(turnedOff == 1)
    }
}
