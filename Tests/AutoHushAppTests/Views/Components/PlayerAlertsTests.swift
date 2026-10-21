import AppKit
import Testing
@testable import AutoHushApp

@Suite("PlayerAlerts")
@MainActor
struct PlayerAlertsTests {
    @Test("a confirmation is a warning with its texts, its button first (Return), then Cancel (Escape); Change… asks with one")
    func confirm() {
        let asked = PlayerAlerts.confirm(title: "Do it?", message: "It's done.", button: "Do It")
        #expect(asked.messageText == "Do it?" && asked.informativeText == "It's done.")
        let change = PlayerAlerts.changeApp("Deezer")
        #expect(change.messageText == "Choose another app?")
        #expect(change.informativeText == "What the check found for Deezer is forgotten.")
        for (alert, button) in [(asked, "Do It"), (change, "Choose Another App")] {
            #expect(alert.alertStyle == .warning)
            #expect(alert.buttons.map(\.title) == [button, "Cancel"])
            #expect(alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1b}"])
        }
    }

    @Test("before an added app is removed: its name asked about, and when it's the player, that another is chosen; Remove answers Return, Cancel Escape")
    func remove() {
        let other = PlayerAlerts.remove("Deezer", isChosen: false)
        #expect(other.messageText == "Remove Deezer?")
        #expect(other.informativeText == "Deezer won’t be offered as a player anymore. The app stays on your Mac. Add an App… can add it back.")
        let chosen = PlayerAlerts.remove("Deezer", isChosen: true)
        #expect(chosen.messageText == "Remove Deezer?")
        #expect(chosen.informativeText == "You’ll choose another player. The app stays on your Mac, and Add an App… can add it back.")
        for alert in [other, chosen] {
            #expect(alert.alertStyle == .warning)
            #expect(alert.buttons.map(\.title) == ["Remove", "Cancel"])
            #expect(alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1b}"])
        }
    }
}
