@testable import AutoHushApp
import AutoHushKit
import AutoHushPlayers
import SpotifySupport
import AutoHushTestSupport

// MARK: - MockLaunchAtLoginController

@MainActor
final class MockLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool
    var setEnabledCalls: [Bool] = []
    /// Override per-test to control what `setEnabled(_:)` returns.
    /// Defaults to `.success(())` so tests that don't set it get a passing result.
    var setEnabledResult: Result<Void, Error> = .success(())
    var openSystemSettingsCallCount = 0

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
        setEnabledCalls.append(enabled)
        switch setEnabledResult {
        case .success:
            isEnabled = enabled
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}
