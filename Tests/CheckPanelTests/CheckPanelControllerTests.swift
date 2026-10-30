import AppKit
import SwiftUI
import Testing
@testable import CheckPanel
@testable import PlayerCheckKit

/// What a panel's content was given: its size and dim callbacks.
@MainActor
private final class Callbacks {
    var dimmed: ((Bool) -> Void)?
}

/// Reads the controller's own panel and shades, not NSApp.windows: another
/// suite's, in the same test process, may still be fading out
/// (WindowTitleTests' check panel).
@Suite("CheckPanelController")
@MainActor
struct CheckPanelControllerTests {
    @Test("at the levels the check lets clicks through on: floating, above the shade while dimmed; the shade under it; hidden, they all go")
    func levels() async throws {
        _ = NSApplication.shared
        let sut = CheckPanelController()
        let callbacks = Callbacks()
        sut.show { _, dimmed in
            callbacks.dimmed = dimmed
            return Text(verbatim: "Checking")
        }
        let panel = try #require(sut.panel)
        #expect(CheckPanelWindows.levels.contains(panel.level.rawValue) && panel.level == .floating)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces) && !panel.canBecomeKey)
        callbacks.dimmed?(true)
        #expect(CheckPanelWindows.levels.contains(panel.level.rawValue) && panel.level == CheckPanelController.panelLevel)
        let shades = sut.shades
        #expect(shades.count == NSScreen.screens.count && shades.allSatisfy(\.isVisible)
            && shades.allSatisfy { $0.level == CheckPanelController.shadeLevel && $0.level.rawValue < panel.level.rawValue })
        sut.hide()
        #expect(!panel.isVisible && sut.panel == nil && sut.shades.isEmpty && !shades.contains(where: \.isVisible))
    }

    @Test("a dim that comes once the panel is hidden puts up no shade with no panel over it")
    func dimAfterHide() throws {
        _ = NSApplication.shared
        let sut = CheckPanelController()
        let callbacks = Callbacks()
        sut.show { _, dimmed in
            callbacks.dimmed = dimmed
            return Text(verbatim: "Checking")
        }
        sut.hide()
        callbacks.dimmed?(true)
        #expect(sut.shades.isEmpty)
    }
}
