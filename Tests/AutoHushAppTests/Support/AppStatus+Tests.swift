import Foundation
@testable import AutoHushApp

extension AppStatus {
    /// Chooses a music player called `name`, as the app does once the user
    /// picks one.
    mutating func choosePlayer(named name: String) {
        let bundleID = "com.example.\(name.lowercased())"
        playerOptions = [PlayerOption(bundleID: bundleID, name: name, appURL: URL(fileURLWithPath: "/Applications/\(name).app"))]
        chosenPlayerID = bundleID
    }
}
