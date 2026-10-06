import AppKit
import Foundation
import os

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
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { !$0.isTerminated }?
            .bundleURL
        guard let appURL = running ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return words(ofAppAt: appURL, read: read)
    }

    /// The words of the app at `appURL`, read once per copy and version.
    package static func words(ofAppAt appURL: URL, read: (URL) -> PlayPauseWords?) -> PlayPauseWords? {
        let version = Bundle(url: appURL)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let key = "\(appURL.path)#\(version)"
        if let cached = cache.withLock({ $0[key] }) { return cached }
        guard let words = read(appURL), !words.play.isEmpty, !words.pause.isEmpty else { return nil }
        cache.withLock { $0[key] = words }
        return words
    }

    private static let cache = OSAllocatedUnfairLock<[String: PlayPauseWords]>(initialState: [:])
}
