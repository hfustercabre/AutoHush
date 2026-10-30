import Foundation
@testable import AutoHushApp

extension AppRelease {
    /// Release `version` as GitHub gives it: its page, and its disk image
    /// with `sha256` unless `diskImage` is false.
    static func github(_ version: String, diskImage: Bool = true, sha256: String? = nil) -> AppRelease {
        AppRelease(
            version: AppVersion(version)!,
            pageURL: URL(string: "https://github.com/hfustercabre/AutoHush/releases/tag/v\(version)")!,
            diskImage: diskImage ? AppRelease.DiskImage(
                url: URL(string: "https://github.com/hfustercabre/AutoHush/releases/download/v\(version)/AutoHush-\(version).dmg")!,
                sha256: sha256
            ) : nil
        )
    }
}
