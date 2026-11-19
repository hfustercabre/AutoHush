import Foundation
import Testing
@testable import AutoHushApp

/// What Diagnostics reads of the chosen player's app.
@Suite("DiagnosticsFacts")
struct DiagnosticsFactsTests {
    @Test("the player's version is read from its Info.plist each time: an app that updated itself in place shows its new one (app-controllers-4)")
    func versionAfterUpdate() throws {
        let app = FileManager.default.temporaryDirectory.appending(path: "Player-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: app) }
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        func install(_ version: String) throws {
            let info: [String: Any] = ["CFBundleIdentifier": "com.example.updating", "CFBundleShortVersionString": version]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appending(path: "Info.plist"))
        }
        try install("1.0")
        #expect(DiagnosticsFacts.version(ofAppAt: app) == "1.0")
        try install("2.0") // updated while AutoHush runs
        #expect(DiagnosticsFacts.version(ofAppAt: app) == "2.0")
        #expect(DiagnosticsFacts.version(ofAppAt: app.appending(path: "Missing.app")) == nil)
    }
}
