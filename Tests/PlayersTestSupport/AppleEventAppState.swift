import Foundation

/// What a scripted app's fake keeps: its process (`nil` while it isn't
/// running), and what it was sent, in order ("ask" for its consent).
package protocol AppleEventAppState: Sendable {
    var pid: pid_t? { get }
    var sent: [String] { get set }
}
