import Testing
@testable import AutoHushKit

@Suite("LogMessage")
struct LogMessageTests {
    @Test("values show when public; text is left out unless marked public, numbers and Booleans show unless marked private")
    func privacy() {
        let name = "Spotify", address = "music.example.com"
        let message: LogMessage = "\(name, privacy: .public) at \(address) after \(3) tries, \(2.5) s, \(true), \(42, privacy: .private)"
        #expect(message.text == "Spotify at <private> after 3 tries, 2.5 s, true, <private>")
        let list: LogMessage = "apps \(["a", "b"]) and \(["c"], privacy: .public)"
        #expect(list.text == "apps <private> and [\"c\"]")
    }
}
