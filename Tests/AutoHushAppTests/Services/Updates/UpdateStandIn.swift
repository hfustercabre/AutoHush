import CryptoKit
import Foundation

/// What a test that opens no disk image downloads, and the requirement it
/// gives the installer: a few bytes and a requirement no copy is checked
/// against, so that only the `.slow` tests make disk images.
enum UpdateStandIn {
    static let contents = Data("not a disk image".utf8)
    static let sha256 = SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined()
    static let requirement = #"identifier "com.autohush.AutoHush""#
}
