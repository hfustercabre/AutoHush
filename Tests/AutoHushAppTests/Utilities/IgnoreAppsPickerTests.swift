import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit

/// The panel that picks apps to ignore: every app it can tell apart is
/// ignored, the others are named in an alert.
@Suite("IgnoreAppsPicker")
@MainActor
struct IgnoreAppsPickerTests {
    @Test("several apps at once: each one that identifies itself is ignored, the others come back to be named")
    func severalApps() {
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        let oldTool = URL(fileURLWithPath: "/Applications/Old Tool.app") // not there: no bundle identifier
        var ignored: [String] = []
        let unidentified = IgnoreAppsPicker.ignoreApps(at: [calculator, oldTool, textEdit]) { ignored.append($0.id) }
        #expect(ignored == ["com.apple.calculator", "com.apple.TextEdit"])
        #expect(unidentified == [oldTool])
    }

    @Test("an app chosen to ignore that can't be told apart says so, by its name")
    func unidentifiedAppAlert() {
        let alert = IgnoreAppsPicker.unidentifiedAppAlert(url: URL(fileURLWithPath: "/Applications/Old Tool.app"))
        #expect(alert.title == "Couldn’t Ignore Old Tool")
        #expect(alert.message.hasPrefix("Old Tool "))
    }
}
