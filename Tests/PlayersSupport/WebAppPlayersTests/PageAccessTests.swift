import Foundation
import Testing
@testable import WebAppPlayers
import AutoHushTestSupport

@Suite("PageAccess")
struct PageAccessTests {
    /// An app bundle with `frameworks` and an Info.plist of `info`, in a
    /// folder of its own (removed after).
    private func app(frameworks: [String] = [], info: [String: String] = [:]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Page-\(UUID().uuidString)")
        return try TestAppBundle.make(in: folder, name: "Page", info: info, frameworks: frameworks)
    }

    @Test("an app's interface, by the frameworks in its bundle; a Chromium web app by its launcher")
    func interfaces() throws {
        let electron = try app(frameworks: ["Electron Framework"]), cef = try app(frameworks: ["Chromium Embedded Framework"])
        let flutter = try app(frameworks: ["FlutterMacOS"]), plain = try app()
        let webApp = try app(info: ["CrAppModeShortcutURL": "https://music.youtube.com/", "CrBundleIdentifier": "com.google.Chrome"])
        defer { [electron, cef, flutter, plain, webApp].forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) } }
        #expect(PageAccess.interface(ofAppAt: electron) == .electron)
        #expect(PageAccess.interface(ofAppAt: cef) == .cef)
        #expect(PageAccess.interface(ofAppAt: flutter) == .flutter)
        #expect(PageAccess.interface(ofAppAt: plain) == .webKit)
        #expect(PageAccess.interface(ofAppAt: webApp) == .chromiumWebApp(browserID: "com.google.Chrome"))
    }

    @Test("Chromium inside Qt shows its page as it is, but its words are current only in sight")
    func qtWebEngine() throws {
        let qt = try app(frameworks: ["QtWebEngineCore"])
        defer { try? FileManager.default.removeItem(at: qt.deletingLastPathComponent()) }
        #expect(PageAccess.interface(ofAppAt: qt) == .qtWebEngine)
        #expect(PageAccess.switches(for: .qtWebEngine).isEmpty)
        #expect(!PageAccess(interface: .qtWebEngine, switchAttribute: nil).wordsCurrentOutOfSight)
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
