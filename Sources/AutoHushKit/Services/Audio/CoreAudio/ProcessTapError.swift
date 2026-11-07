import Foundation

struct ProcessTapError: LocalizedError, LoggableError {
    let step: String
    let status: OSStatus
    var errorDescription: String? { "\(step) failed with OSStatus \(status)" }
    var logDescription: String { errorDescription ?? "\(step) failed" }
}
