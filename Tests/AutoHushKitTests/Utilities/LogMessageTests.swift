import Foundation
import Testing
@testable import AutoHushKit

@Suite("LogMessage")
struct LogMessageTests {
    @Test("values show when public; text is left out unless marked public, numbers and Booleans show unless marked private")
    func privacy() {
        let name = "Streamer", address = "music.example.com"
        let message: LogMessage = "\(name, privacy: .public) at \(address) after \(3) tries, \(2.5) s, \(true), \(42, privacy: .private)"
        #expect(message.text == "Streamer at <private> after 3 tries, 2.5 s, true, <private>")
        let list: LogMessage = "apps \(["a", "b"]) and \(["c"], privacy: .public)"
        #expect(list.text == "apps <private> and [\"c\"]")
    }

    private func text(_ message: LogMessage) -> String { message.text }
    private enum Stuck: Error { case jammed }
    private struct Own: LoggableError { var logDescription: String { "It broke, in English." } }

    @Test("an error says itself in English: AutoHush's own in its words, macOS's by domain and code, others by type and case")
    func errorsInEnglish() {
        let own: any Error = Own()
        #expect(text("failed: \(own)") == "failed: It broke, in English.")
        #expect(text("\(MusicPlayerError.playerNotResponding as any Error)") == "The media player isn’t responding.")

        let offline: any Error = URLError(.notConnectedToInternet)
        #expect(text("\(offline)") == "NSURLErrorDomain error -1009 (not connected to the Internet)")
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: 13)
        let cocoa: any Error = NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [NSUnderlyingErrorKey: underlying])
        #expect(text("\(cocoa)") == "NSCocoaErrorDomain error 513, from NSPOSIXErrorDomain error 13")

        let swift: any Error = Stuck.jammed
        #expect(text("\(swift)") == "jammed")
    }
}
