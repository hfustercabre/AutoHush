import Foundation
@testable import AutoHushApp

/// Stands in for `UpdateInstaller`: records what it's asked to do, and
/// installs nothing.
final class MockUpdateInstaller: UpdateInstalling, @unchecked Sendable {
    private let lock = NSLock()
    private var _unavailability: UpdateInstallUnavailability?
    private var _prepareError: (any Error)?
    private var _calls: [String] = []
    /// Runs while an update is prepared, e.g. to make AutoHush busy meanwhile.
    private let onPrepare: @Sendable () async -> Void

    init(
        unavailability: UpdateInstallUnavailability? = nil,
        prepareError: (any Error)? = nil,
        onPrepare: @escaping @Sendable () async -> Void = {}
    ) {
        _unavailability = unavailability
        _prepareError = prepareError
        self.onPrepare = onPrepare
    }

    /// "prepare 0.3.0", "install 0.3.0", "discard 0.3.0", in order.
    var calls: [String] { lock.withLock { _calls } }

    var unavailability: UpdateInstallUnavailability? { lock.withLock { _unavailability } }

    func prepare(_ release: AppRelease) async throws -> PreparedUpdate {
        record("prepare \(release.version)")
        await onPrepare()
        if let error = lock.withLock({ _prepareError }) { throw error }
        let folder = URL(filePath: "/nonexistent/\(release.version)")
        return PreparedUpdate(version: release.version, app: folder.appending(path: "AutoHush.app"), folder: folder)
    }

    func install(_ update: PreparedUpdate) throws {
        record("install \(update.version)")
    }

    func discard(_ update: PreparedUpdate) {
        record("discard \(update.version)")
    }

    private func record(_ call: String) {
        lock.withLock { _calls.append(call) }
    }
}
