import Foundation
import Testing
import UserNotifications
@testable import AutoHushApp
import AutoHushTestSupport

@Suite("SystemUpdateNotifier", .timeLimit(.minutes(1)))
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
        /// How many times the permission was asked for.
        private(set) var requests = 0
        /// Showing a notice fails while this holds; each try is counted.
        var addFails = false
        private(set) var adds = 0
        let sleep = ManualSleep()

        var center: SystemUpdateNotifier.Center {
            SystemUpdateNotifier.Center(
                status: {
                    self.statusReads += 1
                    return self.status
                },
                requestAuthorization: { self.requests += 1 },
                add: {
                    self.adds += 1
                    if self.addFails { throw CocoaError(.featureUnsupported) }
                    self.shown.append($0.key)
                },
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

    @Test("with notifications off nothing shows; a notice that can't be shown is logged and the next one shows; the permission is asked for only while undetermined, and read as not asked, off or allowed")
    func offAndFailed() async {
        let fake = FakeCenter()
        let notifier = SystemUpdateNotifier(center: fake.center)
        fake.status = .denied
        #expect(await notifier.permission() == .off)
        notifier.requestPermission() // refused already: not asked again
        notifier.announce(.downloaded(v030))
        await TestWait.until { fake.statusReads == 4 } // the permission, the request's look, the notice's two
        #expect(fake.shown.isEmpty && fake.requests == 1) // only the notice's own ask, which macOS answers by itself

        fake.status = .notDetermined
        #expect(await notifier.permission() == .notAsked)
        notifier.requestPermission()
        await TestWait.until { fake.requests == 2 }
        fake.status = .authorized
        #expect(await notifier.permission() == .allowed)
        fake.addFails = true
        notifier.announce(.downloaded(v030))
        await TestWait.until { fake.adds == 1 }
        fake.addFails = false
        notifier.announce(.downloaded(AppVersion("0.3.1")!))
        await TestWait.until { !fake.shown.isEmpty }
        #expect(fake.shown == ["downloaded 0.3.1"] && fake.adds == 2)
    }

    @Test("a click on a notification hands back its notice's kind and version, as it was shown; another action, or what isn't a notice's, nothing",
          arguments: [UpdateNotice.available(AppVersion("0.3.0")!, running: AppVersion("0.2.0")!), .downloaded(AppVersion("0.3.0")!),
                      .installed(AppVersion("0.3.1")!), .installFailed(AppVersion("0.3.1")!)])
    func clickDecoded(_ notice: UpdateNotice) {
        let clicked = UpdateNotice.clicked(action: UNNotificationDefaultActionIdentifier, userInfo: notice.userInfo)
        #expect(clicked?.kind == notice.kind && clicked?.version == notice.version)
        #expect(UpdateNotice.clicked(action: UNNotificationDismissActionIdentifier, userInfo: notice.userInfo) == nil)
        #expect(UpdateNotice.clicked(action: UNNotificationDefaultActionIdentifier, userInfo: ["kind": "other", "version": "0.3.0"]) == nil)
        #expect(UpdateNotice.clicked(action: UNNotificationDefaultActionIdentifier, userInfo: ["kind": notice.kind.rawValue]) == nil)
    }
}
