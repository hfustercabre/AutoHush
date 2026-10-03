import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("AudioSourceIdentifier")
struct AudioSourceIdentifierTests {
    @Test("the outermost app bundle in a path owns it")
    func outermostApp() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        #expect(ProcessAudioSourceIdentifier.outermostBundle(containing: path)?.path == "/Applications/Google Chrome.app")
    }

    @Test("XPC services and extensions outside any app are their own bundle")
    func xpcBundle() {
        let path = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"
        #expect(ProcessAudioSourceIdentifier.outermostBundle(containing: path)?.lastPathComponent == "com.apple.WebKit.GPU.xpc")
    }

    @Test("plain executables have no bundle")
    func noBundle() {
        #expect(ProcessAudioSourceIdentifier.outermostBundle(containing: "/usr/bin/afplay") == nil)
    }

    @Test("a real app bundle yields its identifier, display name and path")
    func realBundle() throws {
        let url = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        try #require(FileManager.default.fileExists(atPath: url.path))
        let source = try #require(ProcessAudioSourceIdentifier.source(forBundleAt: url))
        #expect(source.id == "com.apple.calculator")
        #expect(!source.name.isEmpty && !source.name.hasSuffix(".app"))
        #expect(source.bundlePath == url.path)
    }

    @Test("an unknown process falls back to its own bundle ID")
    func fallback() {
        let process = AudioProcessInfo(objectID: 1, bundleID: "com.example.gone", pid: 999_999)
        #expect(ProcessAudioSourceIdentifier().source(for: process) == AudioSource(id: "com.example.gone", name: "com.example.gone"))
    }

    @Test("a process owner is looked up only while the process exists, and cached consistently")
    func ownerOfProcess() {
        let identifier = ProcessAudioSourceIdentifier()
        #expect(identifier.sourceID(forPID: 999_999) == nil) // no such process
        let own = identifier.sourceID(forPID: getpid())
        #expect(identifier.sourceID(forPID: getpid()) == own)
    }
}
