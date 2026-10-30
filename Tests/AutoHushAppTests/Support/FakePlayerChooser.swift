import Foundation
@testable import AutoHushApp

/// Stands in for the welcome window, so tests never put one on screen.
@MainActor
final class FakePlayerChooser: PlayerChooserPresenting {
    private(set) var isOpen = false
    /// How many times it was brought forward while open.
    private(set) var broughtForward = 0
    /// How many times it was shown.
    private(set) var shown = 0
    func show() { isOpen = true; shown += 1 }
    func bringForward() { if isOpen { broughtForward += 1 } }
    func close() { isOpen = false }
}
