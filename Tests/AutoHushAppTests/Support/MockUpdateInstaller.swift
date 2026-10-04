import Foundation
@testable import AutoHushApp

/// Stands in for `UpdateInstaller`: records what it's asked to do, and
/// installs nothing. A download writes a small file whose SHA-256 it returns.
final class MockUpdateInstaller: UpdateInstalling, @unchecked Sendable {
    private let lock = NSLock()
    private var _unavailability: UpdateInstallUnavailability?
    private var _prepareError: (any Error)?
    private var _downloadError: (any Error)?
    private var _calls: [String] = []
    private var _lowDataModeAllowed: [Bool] = []
    /// Runs while an update is prepared, e.g. to make AutoHush busy meanwhile.
    private let onPrepare: @Sendable () async -> Void

    init(
        unavailability: UpdateInstallUnavailability? = nil,
        prepareError: (any Error)? = nil,
        downloadError: (any Error)? = nil,
        onPrepare: @escaping @Sendable () async -> Void = {}
    ) {
        _unavailability = unavailability
        _prepareError = prepareError
        _downloadError = downloadError
        self.onPrepare = onPrepare
    }

    /// "download 0.3.0", "prepare 0.3.0" (or "prepare 0.3.0 from kept image"),
    /// "install 0.3.0", "discard 0.3.0", in order.
    var calls: [String] { lock.withLock { _calls } }

    /// For each download (to keep, or to install), whether it was allowed
    /// while Low Data Mode is on.
    var lowDataModeAllowed: [Bool] { lock.withLock { _lowDataModeAllowed } }

    var unavailability: UpdateInstallUnavailability? { lock.withLock { _unavailability } }

    var downloadError: (any Error)? {
        get { lock.withLock { _downloadError } }
        set { lock.withLock { _downloadError = newValue } }
    }

    func download(_ release: AppRelease, to file: URL, allowsConstrainedNetwork: Bool) async throws -> String {
        record("download \(release.version)")
        lock.withLock { _lowDataModeAllowed.append(allowsConstrainedNetwork) }
        if let error = downloadError { throw error }
        try Data("AutoHush \(release.version)".utf8).write(to: file)
        return try require(UpdateInstaller.sha256(of: file))
    }

    func prepare(_ release: AppRelease, image: KeptImage?, allowsConstrainedNetwork: Bool) async throws -> PreparedUpdate {
        record(image == nil ? "prepare \(release.version)" : "prepare \(release.version) from kept image")
        if image == nil { lock.withLock { _lowDataModeAllowed.append(allowsConstrainedNetwork) } }
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

/// `#require` for code outside a test: throws when `value` is nil.
private func require<T>(_ value: T?) throws -> T {
    guard let value else { throw CocoaError(.fileReadUnknown) }
    return value
}
