import Foundation

// PlayPauseWords: the words of any app, as Player Check finds them, for an
// app added through a check rather than described by its own module.
extension PlayPauseWords {
    /// Play and Pause as players name them, in English, Spanish, Catalan and
    /// a few more, lowercase and capitalized: what an app's menu item or page
    /// button says when its own words can't be read.
    package static let common: PlayPauseWords = {
        let play = ["play", "reproducir", "reprodueix", "reproduir", "lecture", "lire", "wiedergabe", "abspielen", "riproduci", "reproduzir"]
        let pause = ["pause", "pausa", "pausar", "posa en pausa", "mettre en pause", "pausieren"]
        func cased(_ words: [String]) -> Set<String> { Set(words + words.map { $0.prefix(1).uppercased() + $0.dropFirst() }) }
        return PlayPauseWords(play: cased(play), pause: cased(pause))
    }()

    /// These words and `other`'s together.
    func merged(with other: PlayPauseWords?) -> PlayPauseWords {
        guard let other else { return self }
        return PlayPauseWords(play: play.union(other.play), pause: pause.union(other.pause))
    }

    /// The app's own words for Play and Pause, in every language it has, as
    /// AutoHush's menu players read theirs (TIDAL's, Podcasts'), found the
    /// same way in any app: the texts of a translation table whose English is
    /// "Play" or "Pause" (`.loctable`, as Podcasts'; `*.lproj/*.strings`),
    /// and, in an Electron app's `app.asar`, every text of the keys whose text
    /// is "Play" or "Pause" (as TIDAL's "t-play"); with where they came from.
    /// `nil` when none show.
    package static func found(inAppAt url: URL) -> (words: PlayPauseWords, source: String)? {
        let resources = url.appendingPathComponent("Contents/Resources")
        let files = FileManager.default
        var play: Set<String> = [], pause: Set<String> = [], sources: [String] = []
        func take(_ tables: [[String: String]], english: [String: String], from source: String) {
            let words = tableWords(tables, english: english)
            guard !words.play.isEmpty || !words.pause.isEmpty else { return }
            play.formUnion(words.play)
            pause.formUnion(words.pause)
            sources.append(source)
        }
        let names = (try? files.contentsOfDirectory(atPath: resources.path)) ?? []
        // Every language in one property list (Podcasts' Localizable.loctable).
        for name in names where name.hasSuffix(".loctable") {
            guard let data = try? Data(contentsOf: resources.appendingPathComponent(name), options: .alwaysMapped),
                  let tables = loctable(data) else { continue }
            if let english = tables["en"] ?? tables["English"] ?? tables["Base"] { take(Array(tables.values), english: english, from: name) }
        }
        // One folder per language (Localizable.strings and the like).
        let languages = names.filter { $0.hasSuffix(".lproj") }
        if let englishFolder = ["en.lproj", "English.lproj", "Base.lproj"].first(where: languages.contains) {
            let stringsFiles = ((try? files.contentsOfDirectory(atPath: resources.appendingPathComponent(englishFolder).path)) ?? [])
                .filter { $0.hasSuffix(".strings") }
            for file in stringsFiles {
                func table(_ folder: String) -> [String: String]? {
                    NSDictionary(contentsOf: resources.appendingPathComponent("\(folder)/\(file)")) as? [String: String]
                }
                guard let english = table(englishFolder) else { continue }
                take(languages.compactMap(table), english: english, from: "\(englishFolder)/\(file)")
            }
        }
        // An Electron app's translations, inside app.asar as JSON.
        if let asar = try? Data(contentsOf: resources.appendingPathComponent("app.asar"), options: .alwaysMapped) {
            /// The keys whose text is `word`: `"<key>": "<word>"`.
            func keys(of word: String) -> Set<String> {
                var found: Set<String> = [], start = asar.startIndex
                let marker = Data("\"\(word)\"".utf8)
                while found.count < 8, let range = asar.range(of: marker, in: start..<asar.endIndex) {
                    start = range.upperBound
                    guard range.lowerBound > asar.startIndex else { continue }
                    var colon = range.lowerBound - 1
                    while colon > asar.startIndex, isJSONSpace(asar[colon]) { colon -= 1 }
                    guard asar[colon] == UInt8(ascii: ":") else { continue }
                    var close = colon - 1
                    while close > asar.startIndex, isJSONSpace(asar[close]) { close -= 1 }
                    guard asar[close] == UInt8(ascii: "\"") else { continue }
                    var open = close - 1
                    while open > asar.startIndex, asar[open] != UInt8(ascii: "\""), close - open < 80 { open -= 1 }
                    if let (key, _) = jsonString(at: open, in: asar), !key.isEmpty { found.insert(key) }
                }
                return found
            }
            // Every text of those keys, with or without spaces around the
            // colon, as `keys(of:)` reads them.
            let playTexts = keys(of: "Play").reduce(into: Set<String>()) { $0.formUnion(asarTexts(ofKey: $1, in: asar)) }
            let pauseTexts = keys(of: "Pause").reduce(into: Set<String>()) { $0.formUnion(asarTexts(ofKey: $1, in: asar)) }
            if !playTexts.isEmpty || !pauseTexts.isEmpty {
                play.formUnion(playTexts)
                pause.formUnion(pauseTexts)
                sources.append("app.asar")
            }
        }
        guard !play.isEmpty || !pause.isEmpty else { return nil }
        return (PlayPauseWords(play: play, pause: pause), sources.joined(separator: ", "))
    }
}
