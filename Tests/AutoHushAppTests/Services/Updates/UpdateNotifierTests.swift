import Foundation
import Testing
import UserNotifications
@testable import AutoHushApp
import AutoHushTestSupport

@Suite("SystemUpdateNotifier")
@MainActor
struct UpdateNotifierTests {
    /// Stands in for the Notification Center: AutoHush isn't allowed or
    /// refused until the test answers for the user, and every wait for the
    /// answer waits for the test's next step.
    @MainActor
    private final class FakeCenter {
        var status = UNAuthorizationStatus.notDetermined
        /// How many times the permission was looked at.
        private(set) var statusReads = 0
        /// The notices shown, by their keys.
        private(set) var shown: [String] = []
        private(set) var removals = 0
        let sleep = SteppedSleep()

        var center: SystemUpdateNotifier.Center {
            SystemUpdateNotifier.Center(
                status: {
                    self.statusReads += 1
                    return self.status
                },
                requestAuthorization: {},
                add: { self.shown.append($0.key) },
                remove: { self.removals += 1 },
                sleep: { await self.sleep.sleep($0) }
            )
        }
    }

    private let v030 = AppVersion("0.3.0")!

    @Test("a notice waiting for the permission prompt's answer gives way to a later one, and a withdrawal drops it")
    func noticeWaitingForPermission() async {
        let fake = FakeCenter()
        let notifier = SystemUpdateNotifier(center: fake.center)

        // The first launch, "Notify me": the prompt is up when 0.3.0 is found.
        notifier.announce(.available(v030, running: AppVersion("0.2.0")!))
        await TestWait.until { fake.sleep.sleeping == 1 }
        // "Download it and notify me" chosen meanwhile, then Allow.
        notifier.announce(.downloaded(v030))
        fake.status = .authorized
        fake.sleep.step()
        await TestWait.until { !fake.shown.isEmpty }
        #expect(fake.shown == ["downloaded 0.3.0"])

        // Notifications reset in System Settings: asked again, and the
        // release is withdrawn while the prompt is up.
        fake.status = .notDetermined
        notifier.announce(.available(AppVersion("0.3.1")!, running: AppVersion("0.2.0")!))
        await TestWait.until { fake.sleep.sleeping == 1 }
        notifier.withdraw()
        let reads = fake.statusReads
        fake.status = .authorized
        fake.sleep.step()
        await TestWait.until { fake.statusReads > reads } // the answer is in
        #expect(fake.shown == ["downloaded 0.3.0"])
        #expect(fake.removals == 1)
    }
}
