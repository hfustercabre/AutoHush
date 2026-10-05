import AppKit
import Foundation
import os

/// TIDAL's own words for Play and Pause, in every language it speaks. Its
/// Play/Pause menu item is translated, so these tell its state apart. They're
/// read from TIDAL's translation tables inside its app bundle (`app.asar`),
/// so any language works, including ones TIDAL adds later.
package struct TidalLabels: Equatable, Sendable {
    package let play: Set<String>
    package let pause: Set<String>

    package init(play: Set<String>, pause: Set<String>) {
        self.play = play
        self.pause = pause
    }

    /// Every "t-play" and "t-pause" text in `data`.
    package static func find(in data: Data) -> TidalLabels {
        TidalLabels(play: texts(of: "t-play", in: data), pause: texts(of: "t-pause", in: data))
    }

    /// The labels of the TIDAL installed at `appURL`; `nil` when they can't
    /// be read.
    package static func read(fromAppAt appURL: URL) -> TidalLabels? {
        let asar = appURL.appending(path: "Contents/Resources/app.asar")
        guard let data = try? Data(contentsOf: asar, options: .alwaysMapped) else { return nil }
        let labels = find(in: data)
        return labels.play.isEmpty || labels.pause.isEmpty ? nil : labels
    }

    /// The installed TIDAL's labels, read once per TIDAL version.
    package static func installed() -> TidalLabels? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TidalPlayer.appBundleID) else {
            return nil
        }
        let version = Bundle(url: appURL)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        if let cached = cache.withLock({ $0 }), cached.version == version { return cached.labels }
        guard let labels = read(fromAppAt: appURL) else { return nil }
        cache.withLock { $0 = (version, labels) }
        return labels
    }

    private static let cache = OSAllocatedUnfairLock<(version: String, labels: TidalLabels)?>(initialState: nil)

    /// The values of `"<key>": "…"` in `data`, JSON escapes decoded.
    private static func texts(of key: String, in data: Data) -> Set<String> {
        let marker = Data("\"\(key)\":".utf8)
        var found: Set<String> = []
        var searchStart = data.startIndex
        while let range = data.range(of: marker, in: searchStart..<data.endIndex) {
            searchStart = range.upperBound
            var index = range.upperBound
            while index < data.endIndex, data[index] == UInt8(ascii: " ") { index += 1 }
            guard index < data.endIndex, data[index] == UInt8(ascii: "\"") else { continue }
            var end = index + 1
            while end < data.endIndex, data[end] != UInt8(ascii: "\"") {
                end += data[end] == UInt8(ascii: "\\") ? 2 : 1
            }
            guard end < data.endIndex,
                  let text = try? JSONDecoder().decode(String.self, from: data[index...end]),
                  !text.isEmpty
            else { continue }
            found.insert(text)
        }
        return found
    }
}
