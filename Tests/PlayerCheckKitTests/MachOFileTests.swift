import Foundation
import Testing
@testable import PlayerCheckKit
import AutoHushTestSupport

/// Mach-O files made for the test: a 64-bit one linking `frameworks`, and a
/// universal one holding it as its arm64 slice.
enum MachOSample {
    static func thin(linking frameworks: [String]) -> Data {
        var commands = Data()
        for name in frameworks {
            var path = Data("/System/Library/Frameworks/\(name).framework/Versions/A/\(name)".utf8)
            path.append(0)
            while (24 + path.count) % 8 != 0 { path.append(0) }
            commands.append(words([0xc, UInt32(24 + path.count), 24, 0, 0, 0]))
            commands.append(path)
        }
        var file = words([0xfeed_facf, 0x0100_000c, 0, 2, UInt32(frameworks.count), UInt32(commands.count), 0, 0])
        file.append(commands)
        return file
    }

    static func universal(linking frameworks: [String]) -> Data {
        let slice = thin(linking: frameworks)
        var file = Data([0xca, 0xfe, 0xba, 0xbe]) + bigEndian([2])
        // An x86_64 slice first (pointing at the same bytes), then arm64's.
        file += bigEndian([0x0100_0007, 3, 64, UInt32(slice.count), 0])
        file += bigEndian([0x0100_000c, 0, 64, UInt32(slice.count), 0])
        file += Data(count: 64 - file.count)
        return file + slice
    }

    static func words(_ values: [UInt32]) -> Data { values.reduce(into: Data()) { data, value in withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } } }
    static func bigEndian(_ values: [UInt32]) -> Data { values.reduce(into: Data()) { data, value in withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } } }

    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

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
