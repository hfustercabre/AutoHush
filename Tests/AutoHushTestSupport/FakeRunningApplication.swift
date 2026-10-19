import AppKit

/// An app macOS says opened or quit, as its workspace notices carry it.
package final class FakeRunningApplication: NSRunningApplication, @unchecked Sendable {
    private let fakeBundleID: String
    private let fakeBundleURL: URL?

    package init(bundleID: String, bundleURL: URL? = nil) {
        fakeBundleID = bundleID
        fakeBundleURL = bundleURL
        super.init()
    }

    override package var bundleIdentifier: String? { fakeBundleID }
    override package var bundleURL: URL? { fakeBundleURL }
}
