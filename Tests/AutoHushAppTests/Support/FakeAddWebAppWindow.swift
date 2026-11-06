import Foundation
import os
@testable import AutoHushApp

/// Stands in for the "Add a Web App" window.
@MainActor
final class FakeAddWebAppWindow: AddWebAppPresenting {
    private(set) var isOpen = false
    func show() { isOpen = true }
    func close() { isOpen = false }
    /// The dialogs it moved off, and its moves: "aside", then "back".
    private(set) var obstacles: [CGRect] = []
    private(set) var moves: [String] = []
    private var isAside = false
    func moveAside(of obstacle: CGRect) {
        obstacles.append(obstacle)
        moves.append("aside")
        isAside = true
    }
    func returnFromAside() {
        guard isAside else { return }
        isAside = false
        moves.append("back")
    }
}
