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

    @Test("the media player among the apps chosen is ignored too, and an alert says that counts once another player is chosen")
    func playerAmongThem() {
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        let player = PlayerOption(bundleID: "com.apple.calculator", name: "Calculator", appURL: calculator)
        var ignored: [String] = []
        let alerts = IgnoreAppsPicker.ignoring([calculator, textEdit], player: player) { ignored.append($0.id) }
        #expect(ignored == ["com.apple.calculator", "com.apple.TextEdit"])
        #expect(alerts.map(\.title) == ["Calculator Is Your Media Player"])
        #expect(IgnoreAppsPicker.ignoring([textEdit], player: player) { _ in }.isEmpty)
    }

    @Test("apps chosen to ignore that can't be told apart are named in one alert: by name for one, how many and their names for several, none for none")
    func unidentifiedAppsAlert() throws {
        #expect(IgnoreAppsPicker.unidentifiedAppsAlert(urls: []) == nil)
        let one = try #require(IgnoreAppsPicker.unidentifiedAppsAlert(urls: [URL(fileURLWithPath: "/Applications/Old Tool.app")]))
        #expect(one.title == "Couldn’t Ignore Old Tool")
        #expect(one.message.hasPrefix("Old Tool doesn’t "))
        let urls = ["Old Tool", "Bare Script", "Odd Player"].map { URL(fileURLWithPath: "/Applications/\($0).app") }
        let several = try #require(IgnoreAppsPicker.unidentifiedAppsAlert(urls: urls))
        #expect(several.title == "Couldn’t Ignore 3 Apps")
        #expect(several.message.hasPrefix(ListFormatter.localizedString(byJoining: ["Old Tool", "Bare Script", "Odd Player"]) + " don’t "))
    }
}
