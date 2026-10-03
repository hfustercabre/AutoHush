import Foundation
import OSLog
import ServiceManagement
import AutoHushKit

// MARK: - Protocol

@MainActor
protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Result<Void, Error>
    func openSystemSettings()
}

// MARK: - Implementation

@MainActor
final class LaunchAtLoginController: LaunchAtLoginControlling {
    private let logger = Logger(category: "LaunchAtLogin")
    private let statusProvider: @MainActor () -> SMAppService.Status
    private let registerAction: @MainActor () throws -> Void
    private let unregisterAction: @MainActor () throws -> Void
    private let openSettingsAction: @MainActor () -> Void

    init(
        statusProvider: @escaping @MainActor () -> SMAppService.Status = { SMAppService.mainApp.status },
        registerAction: @escaping @MainActor () throws -> Void = { try SMAppService.mainApp.register() },
        unregisterAction: @escaping @MainActor () throws -> Void = { try SMAppService.mainApp.unregister() },
        openSettingsAction: @escaping @MainActor () -> Void = { SMAppService.openSystemSettingsLoginItems() }
    ) {
        self.statusProvider = statusProvider
        self.registerAction = registerAction
        self.unregisterAction = unregisterAction
        self.openSettingsAction = openSettingsAction
    }

    var isEnabled: Bool { statusProvider() == .enabled }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
        do {
            if enabled { try registerAction() } else { try unregisterAction() }
            return .success(())
        } catch {
            logger.error("Launch at login update failed: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    func openSystemSettings() { openSettingsAction() }
}
