import Foundation
import ServiceManagement
import AutoHushKit

// MARK: - Protocol

@MainActor
protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    /// On, but macOS waits for the user to allow it in Login Items.
    var needsApproval: Bool { get }
    /// Both, from one read of the system (K2-5 of 11-11: Settings asks once
    /// a second while it's open).
    var state: (isEnabled: Bool, needsApproval: Bool) { get }
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Result<Void, any Error>
    func openSystemSettings()
}

extension LaunchAtLoginControlling {
    var state: (isEnabled: Bool, needsApproval: Bool) { (isEnabled, needsApproval) }
}

// MARK: - Implementation

@MainActor
final class LaunchAtLoginController: LaunchAtLoginControlling {
    private let logger = AutoHushLogger(category: "LaunchAtLogin")
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
    var needsApproval: Bool { statusProvider() == .requiresApproval }
    var state: (isEnabled: Bool, needsApproval: Bool) {
        let status = statusProvider() // one query to the system
        return (status == .enabled, status == .requiresApproval)
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Result<Void, any Error> {
        do {
            if enabled { try registerAction() } else { try unregisterAction() }
            AutoHushLogger.settings.info("Launch at login: \(enabled ? "on" : "off", privacy: .public)")
            return .success(())
        } catch {
            logger.error("Launch at login update failed: \(error)")
            return .failure(error)
        }
    }

    func openSystemSettings() { openSettingsAction() }
}
