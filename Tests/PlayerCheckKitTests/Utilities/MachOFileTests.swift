import Foundation
import Testing
@testable import PlayerCheckKit
import AutoHushTestSupport

@Suite("MachOFile and NowPlayingReason")
struct MachOFileTests {
    private let scratch = TemporaryFolder("MachO", create: false)
    private var folder: URL { scratch.url }

    @Test("the frameworks a binary links, thin or universal (its arm64 slice); none for any other file")
    func linked() throws {
        let thin = folder.appendingPathComponent("thin"), fat = folder.appendingPathComponent("fat"), text = folder.appendingPathComponent("text")
        try MachOSample.write(MachOSample.thin(linking: ["MediaPlayer", "AppKit"]), to: thin)
        try MachOSample.write(MachOSample.universal(linking: ["WebKit"]), to: fat)
        try MachOSample.write(Data("#!/bin/sh\n".utf8), to: text)
        #expect(MachOFile.linkedFrameworks(thin) == ["MediaPlayer", "AppKit"])
        #expect(MachOFile.linkedFrameworks(fat) == ["WebKit"])
        #expect(MachOFile.linkedFrameworks(text).isEmpty)
        #expect(MachOFile.linkedFrameworks(folder.appendingPathComponent("missing")).isEmpty)
    }

    @Test("why an app can be in Now Playing, from what its binaries link; a browser's web app by its launcher, named by its browser")
    func reasons() throws {
        let player = folder.appendingPathComponent("Player.app"), electron = folder.appendingPathComponent("Electron.app")
        let plain = folder.appendingPathComponent("Plain.app"), pages = folder.appendingPathComponent("Pages.app")
        let webApp = try TestAppBundle.make(in: folder, name: "Web App",
                                            info: ["CrAppModeShortcutURL": "https://example.com/", "CrBundleIdentifier": "com.example.browser"])
        try MachOSample.write(MachOSample.thin(linking: ["MediaPlayer"]), to: player.appendingPathComponent("Contents/MacOS/Player"))
        try MachOSample.write(MachOSample.thin(linking: ["AppKit"]), to: electron.appendingPathComponent("Contents/MacOS/Electron"))
        try MachOSample.write(MachOSample.thin(linking: ["MediaPlayer"]),
                              to: electron.appendingPathComponent("Contents/Frameworks/Electron Framework.framework/Electron Framework"))
        try MachOSample.write(MachOSample.thin(linking: ["AppKit"]), to: plain.appendingPathComponent("Contents/MacOS/Plain"))
        try MachOSample.write(MachOSample.universal(linking: ["WebKit"]), to: pages.appendingPathComponent("Contents/MacOS/Pages"))
        #expect(NowPlayingReason.of(appAt: player, bundleID: "com.example.player") == "MediaPlayer")
        #expect(NowPlayingReason.of(appAt: electron, bundleID: "com.example.electron") == "MediaPlayer, through Electron")
        #expect(NowPlayingReason.of(appAt: plain, bundleID: "com.example.plain") == nil)
        #expect(NowPlayingReason.of(appAt: pages, bundleID: "com.example.pages") == "WebKit, for the pages it shows")
        #expect(NowPlayingReason.of(appAt: plain, bundleID: "com.apple.Safari.WebApp.ABC") == "WebKit, as a Safari web app")
        // A browser Launch Services doesn't know is named by its bundle ID.
        #expect(NowPlayingReason.of(appAt: webApp, bundleID: "com.example.browser.app.abc") == "Chromium, as a com.example.browser web app")
    }
}
