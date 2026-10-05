import Foundation
@testable import AutoHushApp

/// Stands in for the welcome window, so tests never put one on screen.
@MainActor
final class FakePlayerChooser: PlayerChooserPresenting {
    private(set) var isVisible = false
    func show() { isVisible = true }
    func close() { isVisible = false }
}

extension AppStatus {
    /// Chooses a music player called `name`, as the app does once the user
    /// picks one.
    mutating func choosePlayer(named name: String) {
        let bundleID = "com.example.\(name.lowercased())"
        playerOptions = [PlayerOption(bundleID: bundleID, name: name, appURL: URL(fileURLWithPath: "/Applications/\(name).app"))]
        chosenPlayerID = bundleID
    }
}
