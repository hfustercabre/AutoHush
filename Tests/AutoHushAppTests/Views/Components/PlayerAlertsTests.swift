import AppKit
import Testing
@testable import AutoHushApp

@Suite("PlayerAlerts")
@MainActor
struct PlayerAlertsTests {
    @Test("before an added app is removed: its name asked about, a sentence more when it's the player; Remove answers Return, Cancel Escape")
    func remove() {
        let other = PlayerAlerts.remove("Deezer", isChosen: false)
        #expect(other.messageText == "Remove Deezer?")
        #expect(other.informativeText == "Deezer won’t be offered as a player anymore. The app stays on your Mac. Add an App… can add it back.")
        let chosen = PlayerAlerts.remove("Deezer", isChosen: true)
        #expect(chosen.messageText == "Remove Deezer?")
        #expect(chosen.informativeText == "It’s your current player, so you’ll choose another. " + other.informativeText)
        for alert in [other, chosen] {
            #expect(alert.alertStyle == .warning)
            #expect(alert.buttons.map(\.title) == ["Remove", "Cancel"])
            #expect(alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1b}"])
        }
    }
}
