import Testing
@testable import AutoHushApp
import AutoHushTestSupport

@Suite("Copied feedback", .waitsTimeLimit)
@MainActor
struct CopiedFeedbackTests {
    @Test("Copied shows for its moment after a click; a click meanwhile starts the moment over, so the first one's end doesn't cut it short")
    func secondClickStartsOver() async {
        let sleep = ManualSleep()
        let copied = CopiedFeedback(sleep: sleep.sleep)
        #expect(!copied.isShown)
        copied.show()
        #expect(copied.isShown)
        await TestWait.until { sleep.sleeping == 1 }
        copied.show() // the first moment ends as it's cancelled
        await TestWait.until { sleep.sleeping == 1 }
        #expect(copied.isShown)
        sleep.step()
        await TestWait.until { !copied.isShown }
    }
}
