import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport
import CheckedPlayers

/// The controls' Details… sheet, drawn as its window draws it (B-5, T-8,
/// the full check, 2026-11-06).
@Suite("ControlDetailsView", .application)
@MainActor
struct ControlDetailsViewTests {
    @Test("it draws with backups on and off, off with its note under their heading; the Play/Pause key says when it's pressed")
    func draws() {
        let on = drawn(ControlDetailsView(player: "Jukebox", controls: .choosing(), done: {}), width: 440)
        let off = drawn(ControlDetailsView(player: "Jukebox", controls: .choosing(switches: BackupSwitches(usesBackups: false)),
                                           done: {}), width: 440)
        #expect(on.width == 440 && on.height > 0)
        #expect(off.height > on.height) // "Use backup controls is off"
        // The key, which no check tries, drawn with its note: taller than
        // another control not tried, which has none (T-10 of 11-11).
        let notTried = { (kind: WayOrder.Kind) in
            drawn(ControlDetailsView(player: "Jukebox",
                                     controls: PlayerControls(main: .init(kind: .script, result: nil),
                                                              backups: [.init(kind: kind, result: nil)],
                                                              switches: BackupSwitches()),
                                     done: {}), width: 440)
        }
        #expect(notTried(.mediaKey).height > notTried(.menu).height)
        #expect(BackupText.keyNote("Jukebox") == "Only while Jukebox is Now Playing")
    }

    @Test("a player with no backups draws its main control alone")
    func mainOnly() {
        let controls = PlayerControls(main: .init(kind: .script, result: nil), backups: [], switches: BackupSwitches())
        let alone = drawn(ControlDetailsView(player: "Jukebox", controls: controls, done: {}), width: 440)
        let all = drawn(ControlDetailsView(player: "Jukebox", controls: .choosing(), done: {}), width: 440)
        #expect(alone.height > 0 && alone.height < all.height)
    }
}
