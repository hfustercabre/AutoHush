import Testing
@testable import AutoHushApp
import AutoHushKit

/// What Settings → General and Settings → Media Player say the chosen
/// player lacks to be controlled (U7a): one text for both pages.
@Suite("The missing control permission's note")
@MainActor
struct ControlPermissionNoteTests {
    @Test("it says nothing once the player's control permission is allowed or not needed", arguments: [
        Permission.automation(player: "Jukebox"), .accessibility(player: "Jukebox"),
    ])
    func nothingOnceAllowed(_ permission: Permission) {
        for access: PermissionAccess in [.allowed, .notNeeded] {
            #expect(ControlPermissionNote.note(permission, access: access, player: "Jukebox") == nil, "\(access)")
        }
    }

    @Test("it names the permission missing, and the player to open while Automation waits for it to run")
    func words() {
        #expect(ControlPermissionNote.note(.automation(player: "Jukebox"), access: .denied, player: "Jukebox")
            == "AutoHush can’t control Jukebox without Automation access.")
        #expect(ControlPermissionNote.note(.accessibility(player: "Jukebox"), access: .notAsked, player: "Jukebox")
            == "AutoHush can’t control Jukebox without Accessibility access.")
        #expect(ControlPermissionNote.note(.automation(player: "Jukebox"), access: .playerNotRunning, player: "Jukebox")
            == PermissionText.controlNote("Jukebox", .playerNotRunning))
    }
}
