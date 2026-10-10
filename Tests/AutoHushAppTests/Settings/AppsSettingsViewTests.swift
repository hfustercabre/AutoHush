import Foundation
import Testing
@testable import AutoHushApp

@Suite("Settings → Apps")
@MainActor
struct AppsSettingsViewTests {
    @Test("an app chosen to ignore that can't be told apart says so, by its name")
    func unidentifiedAppAlert() {
        let alert = AppsSettingsView.unidentifiedAppAlert(url: URL(fileURLWithPath: "/Applications/Old Tool.app"))
        #expect(alert.title == "Couldn't Ignore Old Tool")
        #expect(alert.message.hasPrefix("Old Tool "))
    }
}
