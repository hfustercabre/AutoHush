import Foundation

package enum StubError: Error, LocalizedError {
    case failed
    package var errorDescription: String? { "stub failed" }
}
