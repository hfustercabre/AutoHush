import Foundation

/// Installs updates. `UpdateInstaller` is the real one; tests stand in for it.
protocol UpdateInstalling: Sendable {
    /// Why this copy can't update itself, or nil when it can.
    var unavailability: UpdateInstallUnavailability? { get }
    /// Downloads `release`'s disk image to `file`, checked against the
    /// SHA-256 GitHub lists for it, and returns the file's SHA-256. Without
    /// `allowsConstrainedNetwork`, it doesn't download while Low Data Mode is on.
    func download(_ release: AppRelease, to file: URL, allowsConstrainedNetwork: Bool) async throws -> String
    /// Gets `release` ready to install and checks it: from `image`, an
    /// earlier download, when given, otherwise downloaded now (see `download`
    /// for `allowsConstrainedNetwork`).
    func prepare(_ release: AppRelease, image: KeptImage?, allowsConstrainedNetwork: Bool) async throws -> PreparedUpdate
    /// Puts `update` in the running app's place, to be opened once AutoHush quits.
    func install(_ update: PreparedUpdate) throws
    /// Deletes a prepared update that won't be installed.
    func discard(_ update: PreparedUpdate)
}
