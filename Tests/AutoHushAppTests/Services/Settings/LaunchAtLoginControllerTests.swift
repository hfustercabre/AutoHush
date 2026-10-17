import ServiceManagement
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

@Suite("LaunchAtLoginController")
struct LaunchAtLoginControllerTests {

    // MARK: - isEnabled, needsApproval

    @MainActor
    @Test("on only once registered; waiting for the user's approval in Login Items says so",
          arguments: [(SMAppService.Status.enabled, true, false), (.notRegistered, false, false),
                      (.requiresApproval, false, true), (.notFound, false, false)])
    func status(status: SMAppService.Status, isEnabled: Bool, needsApproval: Bool) {
        let controller = LaunchAtLoginController(
            statusProvider: { status },
            registerAction: { },
            unregisterAction: { },
            openSettingsAction: { }
        )
        #expect(controller.isEnabled == isEnabled)
        #expect(controller.needsApproval == needsApproval)
    }

    // MARK: - setEnabled

    @MainActor
    @Test("on registers, off unregisters, and a failure comes back as one", arguments: [true, false], [true, false])
    func setEnabled(enabled: Bool, fails: Bool) {
        var calls: [String] = []
        let controller = LaunchAtLoginController(
            statusProvider: { .notRegistered },
            registerAction: {
                calls.append("register")
                if fails { throw StubError.failed }
            },
            unregisterAction: {
                calls.append("unregister")
                if fails { throw StubError.failed }
            },
            openSettingsAction: { }
        )

        let result = controller.setEnabled(enabled)

        #expect(calls == [enabled ? "register" : "unregister"])
        switch result {
        case .success: #expect(!fails)
        case .failure(let error): #expect(fails && error.localizedDescription == "stub failed")
        }
    }

    // MARK: - openSystemSettings

    @MainActor
    @Test("openSystemSettings delegates to the injected action")
    func openSystemSettingsDelegates() {
        var openCount = 0
        let controller = LaunchAtLoginController(
            statusProvider: { .notRegistered },
            registerAction: { },
            unregisterAction: { },
            openSettingsAction: { openCount += 1 }
        )

        controller.openSystemSettings()

        #expect(openCount == 1)
    }
}
