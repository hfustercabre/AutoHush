import Foundation

// PlayPauseWords: reading an app's translations, as TIDAL's, Podcasts' and
// any app's words (`found`) are read: a translation table's texts by their
// English, and the texts of a key in an Electron app's `app.asar`.
extension PlayPauseWords {
    /// In each of `tables` (one language's `[key: text]`), the texts of the
    /// keys whose English (`english`) is "Play" or "Pause".
    package static func tableWords(_ tables: some Sequence<[String: String]>, english: [String: String]) -> PlayPauseWords {
        let playKeys = english.filter { $0.value == "Play" }.keys, pauseKeys = english.filter { $0.value == "Pause" }.keys
        var play: Set<String> = [], pause: Set<String> = []
        for table in tables {
            play.formUnion(playKeys.compactMap { table[$0] })
            pause.formUnion(pauseKeys.compactMap { table[$0] })
        }
        return PlayPauseWords(play: play, pause: pause)
    }

    /// The languages of a translation table with every language in one
    /// property list (a `.loctable`, as Podcasts' Localizable.loctable):
    /// `[language: [key: text]]`, only the keys with a text. `nil` when it
    /// isn't one.
    package static func loctable(_ data: Data) -> [String: [String: String]]? {
        guard let languages = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return nil }
        return languages.compactMapValues { ($0 as? [String: Any])?.compactMapValues { $0 as? String } }
    }

    /// Every text of `key` in an Electron app's `app.asar`: `"<key>": "…"`,
    /// with or without spaces around the colon, JSON escapes decoded.
    package static func asarTexts(ofKey key: String, in asar: Data) -> Set<String> {
        var found: Set<String> = [], start = asar.startIndex
        let marker = Data("\"\(key)\"".utf8)
        while let range = asar.range(of: marker, in: start..<asar.endIndex) {
            start = range.upperBound
            var index = range.upperBound
            while index < asar.endIndex, isJSONSpace(asar[index]) { index += 1 }
            guard index < asar.endIndex, asar[index] == UInt8(ascii: ":") else { continue }
            index += 1
            while index < asar.endIndex, isJSONSpace(asar[index]) { index += 1 }
            if let (text, _) = jsonString(at: index, in: asar), !text.isEmpty { found.insert(text) }
        }
        return found
    }

    /// JSON's white space, between a key, its colon and its text.
    static func isJSONSpace(_ byte: UInt8) -> Bool { [0x20, 0x09, 0x0A, 0x0D].contains(byte) }

    /// The JSON string starting at `index` (a quote) in `data`, decoded, and
    /// the index after it; `nil` for none, or one of 200 bytes or more.
    static func jsonString(at index: Data.Index, in data: Data) -> (String, Data.Index)? {
        guard index >= data.startIndex, index < data.endIndex, data[index] == UInt8(ascii: "\"") else { return nil }
        var end = index + 1
        while end < data.endIndex, data[end] != UInt8(ascii: "\"") { end += data[end] == UInt8(ascii: "\\") ? 2 : 1 }
        guard end < data.endIndex, end - index < 200, let text = try? JSONDecoder().decode(String.self, from: data[index...end]) else { return nil }
        return (text, end + 1)
    }
}
