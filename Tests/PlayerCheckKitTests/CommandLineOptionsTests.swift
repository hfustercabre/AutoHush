import Testing
@testable import PlayerCheckKit

@Suite("CommandLineOptions")
struct CommandLineOptionsTests {
    @Test("the app is the argument that's neither an option nor an option's value, wherever it comes")
    func app() {
        #expect(CommandLineOptions.app(in: ["/Applications/Player.app", "--block-input", "--partial", "--result", "/tmp/r.json",
                                            "--logs", "/tmp/logs", "--caches", "/tmp/caches", "--no-taps"]) == "/Applications/Player.app")
        #expect(CommandLineOptions.app(in: ["--logs", "/tmp/logs", "Player", "--via", "page", "--pause"]) == "Player")
        #expect(CommandLineOptions.app(in: [CommandLineOptions.developer, "/Applications/Player.app", "--block-input"]) == "/Applications/Player.app")
        #expect(CommandLineOptions.app(in: ["--read-only"]) == nil)
    }

    @Test("a query's operands leave out the folders AutoHush passes")
    func operands() {
        let reasons = ["/Applications/A.app", "/Applications/B.app", "--logs", "/Users/x/Library/Logs/AutoHush/Checks",
                       "--caches", "/Users/x/Library/Caches/com.autohush.AutoHush/PlayerCheck"]
        #expect(CommandLineOptions.operands(in: reasons) == ["/Applications/A.app", "/Applications/B.app"])
        #expect(CommandLineOptions.operands(in: ["24", "--logs", "/l", "--caches", "/c"]) == ["24"])
        #expect(CommandLineOptions.developer == "--developer")
        #expect(!CommandLineOptions.withValues.contains(CommandLineOptions.developer))
        #expect(CommandLineOptions.value(of: "--caches", in: reasons) == "/Users/x/Library/Caches/com.autohush.AutoHush/PlayerCheck")
        #expect(CommandLineOptions.value(of: "--result", in: reasons) == nil)
        #expect(CommandLineOptions.value(of: "--logs", in: ["--logs"]) == nil)
    }
}
