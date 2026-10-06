import Foundation
import MenuPlayers

/// TIDAL's words for Play and Pause: every "t-play" and "t-pause" text in its
/// translation tables, which are inside its app bundle (`app.asar`).
enum TidalWords {
    /// Every "t-play" and "t-pause" text in `data`.
    static func find(in data: Data) -> PlayPauseWords {
        PlayPauseWords(play: texts(of: "t-play", in: data), pause: texts(of: "t-pause", in: data))
    }

    /// The words of the TIDAL at `appURL`; `nil` when they can't be read.
    static func read(fromAppAt appURL: URL) -> PlayPauseWords? {
        let asar = appURL.appending(path: "Contents/Resources/app.asar")
        guard let data = try? Data(contentsOf: asar, options: .alwaysMapped) else { return nil }
        return find(in: data)
    }

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
