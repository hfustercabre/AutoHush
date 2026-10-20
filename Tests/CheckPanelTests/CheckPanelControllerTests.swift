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

/// One test at a time; each counts only the shades made since it started
/// (`before`): another suite's, in the same test process, may still be
/// fading out (WindowTitleTests' check panel).
@Suite("CheckPanelController", .serialized)
@MainActor
struct CheckPanelControllerTests {
    private func shades(since before: Set<ObjectIdentifier>) -> [NSWindow] {
        NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) && $0.level == CheckPanelController.shadeLevel && $0.isVisible }
    }

    @Test("at the levels the check lets clicks through on: floating, above the shade while dimmed; the shade under it; hidden, they all go")
    func levels() async throws {
        _ = NSApplication.shared
        let sut = CheckPanelController()
        let callbacks = Callbacks()
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        sut.show { _, dimmed in
            callbacks.dimmed = dimmed
            return Text(verbatim: "Checking")
        }
        let panel = try #require(NSApp.windows.first { !before.contains(ObjectIdentifier($0)) } as? NSPanel)
        #expect(CheckPanelWindows.levels.contains(panel.level.rawValue) && panel.level == .floating)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces) && !panel.canBecomeKey)
        callbacks.dimmed?(true)
        #expect(CheckPanelWindows.levels.contains(panel.level.rawValue) && panel.level == CheckPanelController.panelLevel)
        #expect(shades(since: before).count == NSScreen.screens.count
            && shades(since: before).allSatisfy { $0.level.rawValue < panel.level.rawValue })
        sut.hide()
        #expect(!panel.isVisible && shades(since: before).isEmpty)
    }

    @Test("a dim that comes once the panel is hidden puts up no shade with no panel over it")
    func dimAfterHide() throws {
        _ = NSApplication.shared
        let sut = CheckPanelController()
        let callbacks = Callbacks()
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        sut.show { _, dimmed in
            callbacks.dimmed = dimmed
            return Text(verbatim: "Checking")
        }
        sut.hide()
        callbacks.dimmed?(true)
        #expect(shades(since: before).isEmpty)
    }
}
