import Foundation

/// A folder of a test's own in the temporary folder, named by `prefix` and a
/// UUID, and removed with its last reference: also when the test throws
/// before its end. Kept by a test's harness, or by the test until its last
/// line (`withExtendedLifetime`), since a local can be released early.
package final class TemporaryFolder: Sendable {
    package let url: URL

    /// `create` false leaves it to the code under test to make it.
    package init(_ prefix: String, create: Bool = true) {
        url = FileManager.default.temporaryDirectory.appending(path: "\(prefix)-\(UUID().uuidString)")
        if create { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    }

    package func appending(path: String) -> URL { url.appending(path: path) }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
