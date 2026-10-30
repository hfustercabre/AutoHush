import Foundation
import os
@testable import AutoHushApp

/// Stands in for the "Add a Web App" window.
@MainActor
final class FakeAddWebAppWindow: AddWebAppPresenting {
    private(set) var isOpen = false
    func show() { isOpen = true }
    func close() { isOpen = false }
}
