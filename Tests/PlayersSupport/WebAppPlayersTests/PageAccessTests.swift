import Foundation
import Testing
@testable import WebAppPlayers

@Suite("PageAccess")
struct PageAccessTests {
    /// An app bundle with `frameworks` and an Info.plist of `info`.
    private func app(frameworks: [String] = [], info: [String: String] = [:]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Page-\(UUID().uuidString).app")
        for name in frameworks {
            try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents/Frameworks/\(name).framework"),
                                                    withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        #expect((info as NSDictionary).write(to: url.appendingPathComponent("Contents/Info.plist"), atomically: true))
        return url
    }

    @Test("an app's interface, by the frameworks in its bundle; a Chromium web app by its launcher")
    func interfaces() throws {
        let electron = try app(frameworks: ["Electron Framework"]), cef = try app(frameworks: ["Chromium Embedded Framework"])
        let flutter = try app(frameworks: ["FlutterMacOS"]), plain = try app()
        let webApp = try app(info: ["CrAppModeShortcutURL": "https://music.youtube.com/", "CrBundleIdentifier": "com.google.Chrome"])
        defer { [electron, cef, flutter, plain, webApp].forEach { try? FileManager.default.removeItem(at: $0) } }
        #expect(PageAccess.interface(ofAppAt: electron) == .electron)
        #expect(PageAccess.interface(ofAppAt: cef) == .cef)
        #expect(PageAccess.interface(ofAppAt: flutter) == .flutter)
        #expect(PageAccess.interface(ofAppAt: plain) == .webKit)
        #expect(PageAccess.interface(ofAppAt: webApp) == .chromiumWebApp(browserID: "com.google.Chrome"))
    }

    @Test("the switches tried for each, in order, and what each page is like")
    func switches() {
        #expect(PageAccess.switches(for: .webKit).isEmpty)
        #expect(PageAccess.switches(for: .electron) == [PageAccess.electronSwitch])
        #expect(PageAccess.switches(for: .cef) == [PageAccess.electronSwitch, PageAccess.voiceOverSwitch])
        #expect(PageAccess.switches(for: .chromiumWebApp(browserID: "com.google.Chrome")) == [PageAccess.voiceOverSwitch])
        #expect(PageAccess.webKit.wordsCurrentOutOfSight)
        #expect(!PageAccess(interface: .cef, switchAttribute: PageAccess.voiceOverSwitch).wordsCurrentOutOfSight)
        #expect(PageAccess(interface: .flutter, switchAttribute: PageAccess.voiceOverSwitch).pageIsWindow)
        #expect(PageAccess(interface: .chromiumWebApp(browserID: "com.brave.Browser"), switchAttribute: nil).browserID == "com.brave.Browser")
    }

    @Test("kept as found")
    func kept() throws {
        let access = PageAccess(interface: .chromiumWebApp(browserID: "com.google.Chrome"), switchAttribute: PageAccess.voiceOverSwitch)
        #expect(try JSONDecoder().decode(PageAccess.self, from: JSONEncoder().encode(access)) == access)
    }
}
