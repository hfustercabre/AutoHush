import AppKit
import Foundation
import os
import AutoHushKit

/// An app's own words for Play and Pause, in every language it speaks. Its
/// Play/Pause menu item is translated, so these tell its state apart. Each
/// app's support reads them from the app's bundle, so any language works,
/// including ones the app adds later.
package struct PlayPauseWords: Equatable, Sendable {
    package let play: Set<String>
    package let pause: Set<String>

    package init(play: Set<String>, pause: Set<String>) {
        self.play = play
        self.pause = pause
    }

    /// The words of the app running with `bundleID`, so they match its
    /// version; while none runs, of the copy Launch Services knows. `read`
    /// reads them from a copy of the app.
    package static func installed(bundleID: String, read: (URL) -> PlayPauseWords?) -> PlayPauseWords? {
        let running = NSRunningApplication.running(bundleID)?.bundleURL
        guard let appURL = running ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return words(ofAppAt: appURL, read: read)
    }

    /// The words of the app at `appURL`, read once per copy and version.
    /// When they can't be read (the app changed how it keeps them), it's
    /// logged once per copy and version: AutoHush can't tell its state then.
    package static func words(ofAppAt appURL: URL, read: (URL) -> PlayPauseWords?) -> PlayPauseWords? {
        let version = Bundle(url: appURL)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let key = "\(appURL.path)#\(version)"
        if let cached = cache.withLock({ $0[key] }) { return cached }
        guard let words = read(appURL), !words.play.isEmpty, !words.pause.isEmpty else {
            if failed.withLock({ $0.insert(key).inserted }) {
                logger.error("Couldn't read the words for Play and Pause of \(appURL.lastPathComponent, privacy: .public) \(version, privacy: .public)")
            }
            return nil
        }
        cache.withLock { $0[key] = words }
        return words
    }

    private static let cache = OSAllocatedUnfairLock<[String: PlayPauseWords]>(initialState: [:])
    /// The copies and versions whose words couldn't be read, already logged.
    private static let failed = OSAllocatedUnfairLock<Set<String>>(initialState: [])
    private static let logger = Logger(category: "MenuPlayer")
}
