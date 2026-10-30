import Foundation
import os
@testable import AutoHushApp

/// Stands in for the learning window, so tests never put one on screen.
@MainActor
final class FakeLearningWindow: LearningWindowPresenting {
    private(set) var isOpen = false
    private(set) var shownCount = 0
    var onClose: (@MainActor () -> Void)?
    func show() {
        isOpen = true
        shownCount += 1
    }
    /// As Later or the close button: the window says it closed.
    func close() {
        guard isOpen else { return }
        isOpen = false
        onClose?()
    }
}
