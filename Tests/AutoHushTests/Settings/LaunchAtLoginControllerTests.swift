import ServiceManagement
import Testing
@testable import AutoHush

@Suite("LaunchAtLoginController")
struct LaunchAtLoginControllerTests {

    // MARK: - isEnabled

    @MainActor
    @Test("isEnabled is true when status provider returns .enabled")
    func isEnabledWhenStatusEnabled() {
        let controller = LaunchAtLoginController(
            statusProvider: { .enabled },
            registerAction: { },
            unregisterAction: { },
            openSettingsAction: { }
        )
        #expect(controller.isEnabled == true)
    }

    @MainActor
    @Test("isEnabled is false when status provider returns .notRegistered")
    func isEnabledWhenStatusNotRegistered() {
        let controller = LaunchAtLoginController(
            statusProvider: { .notRegistered },
            registerAction: { },
            unregisterAction: { },
            openSettingsAction: { }
        )
        #expect(controller.isEnabled == false)
    }

    // MARK: - setEnabled

    @MainActor
    @Test("setEnabled(true) calls register and returns success")
    func enablingCallsRegister() {
        var registerCount = 0
        var unregisterCount = 0
        let controller = LaunchAtLoginController(
            statusProvider: { .notRegistered },
            registerAction: { registerCount += 1 },
            unregisterAction: { unregisterCount += 1 },
            openSettingsAction: { }
        )

        let result = controller.setEnabled(true)

        #expect(registerCount == 1)
        #expect(unregisterCount == 0)
        if case .failure(let error) = result {
            Issue.record("Expected success, got: \(error)")
        }
    }

    @MainActor
    @Test("setEnabled(false) calls unregister and returns success")
    func disablingCallsUnregister() {
        var registerCount = 0
        var unregisterCount = 0
        let controller = LaunchAtLoginController(
            statusProvider: { .enabled },
            registerAction: { registerCount += 1 },
            unregisterAction: { unregisterCount += 1 },
            openSettingsAction: { }
        )

        let result = controller.setEnabled(false)

        #expect(registerCount == 0)
        #expect(unregisterCount == 1)
        if case .failure(let error) = result {
            Issue.record("Expected success, got: \(error)")
        }
    }

    @MainActor
    @Test("setEnabled returns failure when register action throws")
    func enablingReturnsFailureOnThrow() {
        let controller = LaunchAtLoginController(
            statusProvider: { .notRegistered },
            registerAction: { throw StubError.failed },
            unregisterAction: { },
            openSettingsAction: { }
        )

        let result = controller.setEnabled(true)

        guard case .failure(let error) = result else {
            Issue.record("Expected failure")
            return
        }
        #expect(error.localizedDescription == "stub failed")
    }

    @MainActor
    @Test("setEnabled returns failure when unregister action throws")
    func disablingReturnsFailureOnThrow() {
        let controller = LaunchAtLoginController(
            statusProvider: { .enabled },
            registerAction: { },
            unregisterAction: { throw StubError.failed },
            openSettingsAction: { }
        )

        let result = controller.setEnabled(false)

        guard case .failure(let error) = result else {
            Issue.record("Expected failure")
            return
        }
        #expect(error.localizedDescription == "stub failed")
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
