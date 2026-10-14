import Foundation

/// A release's disk image downloaded earlier and kept, with the SHA-256 it
/// had then.
struct KeptImage: Equatable, Sendable {
    let file: URL
    let sha256: String
}
