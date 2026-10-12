import AppKit
import AutoHushKit
import MenuPlayers
import WebAppPlayers

// MARK: - The app's own words for Play and Pause

/// The app's own words for Play and Pause, in every language it has, as
/// AutoHush's menu players read theirs (TidalWords, PodcastsWords), found the
/// same way in any app: the texts of a translation table whose English is
/// "Play" or "Pause" (`.loctable`, as Podcasts'; `*.lproj/*.strings`), and,
/// in an Electron app's `app.asar`, every text of the keys whose text is
/// "Play" or "Pause" (as TIDAL's "t-play"). Read once per copy and version
/// (kept in ~/Library/Caches/PlayerCheck/words.json); nil when none show.
func appWords(of url: URL) -> (words: PlayPauseWords, source: String)? {
    struct Kept: Codable { var play: [String]; var pause: [String]; var source: String }
    let cacheFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/PlayerCheck/words.json")
    let key = "\(url.path)#\(Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")"
    var cache = (try? JSONDecoder().decode([String: Kept?].self, from: Data(contentsOf: cacheFile))) ?? [:]
    if let kept = cache[key] {
        return kept.map { (PlayPauseWords(play: Set($0.play), pause: Set($0.pause)), $0.source) }
    }
    let resources = url.appendingPathComponent("Contents/Resources")
    let files = FileManager.default
    var play: Set<String> = [], pause: Set<String> = [], sources: [String] = []
    func take(_ tables: [[String: String]], english: [String: String], from source: String) {
        let playKeys = english.filter { $0.value == "Play" }.keys, pauseKeys = english.filter { $0.value == "Pause" }.keys
        guard !playKeys.isEmpty || !pauseKeys.isEmpty else { return }
        for table in tables {
            play.formUnion(playKeys.compactMap { table[$0] })
            pause.formUnion(pauseKeys.compactMap { table[$0] })
        }
        sources.append(source)
    }
    let names = (try? files.contentsOfDirectory(atPath: resources.path)) ?? []
    // Every language in one property list (Podcasts' Localizable.loctable).
    for name in names where name.hasSuffix(".loctable") {
        guard let data = try? Data(contentsOf: resources.appendingPathComponent(name), options: .alwaysMapped),
              let languages = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { continue }
        let tables = languages.compactMapValues { ($0 as? [String: Any])?.compactMapValues { $0 as? String } }
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
        /// The JSON string starting at `index` (a quote), decoded, and the index after it.
        func string(at index: Data.Index) -> (String, Data.Index)? {
            guard index >= asar.startIndex, index < asar.endIndex, asar[index] == UInt8(ascii: "\"") else { return nil }
            var end = index + 1
            while end < asar.endIndex, asar[end] != UInt8(ascii: "\"") { end += asar[end] == UInt8(ascii: "\\") ? 2 : 1 }
            guard end < asar.endIndex, end - index < 200, let text = try? JSONDecoder().decode(String.self, from: asar[index...end]) else { return nil }
            return (text, end + 1)
        }
        /// The keys whose text is `word`: `"<key>": "<word>"`.
        func keys(of word: String) -> Set<String> {
            var found: Set<String> = [], start = asar.startIndex
            let marker = Data("\"\(word)\"".utf8)
            while found.count < 8, let range = asar.range(of: marker, in: start..<asar.endIndex) {
                start = range.upperBound
                guard range.lowerBound > asar.startIndex else { continue }
                var colon = range.lowerBound - 1
                while colon > asar.startIndex, asar[colon] == UInt8(ascii: " ") { colon -= 1 }
                guard asar[colon] == UInt8(ascii: ":") else { continue }
                var close = colon - 1
                while close > asar.startIndex, asar[close] == UInt8(ascii: " ") { close -= 1 }
                guard asar[close] == UInt8(ascii: "\"") else { continue }
                var open = close - 1
                while open > asar.startIndex, asar[open] != UInt8(ascii: "\""), close - open < 80 { open -= 1 }
                if let (key, _) = string(at: open), !key.isEmpty { found.insert(key) }
            }
            return found
        }
        /// Every text of `key`: `"<key>": "…"`.
        func texts(of key: String) -> Set<String> {
            var found: Set<String> = [], start = asar.startIndex
            let marker = Data("\"\(key)\":".utf8)
            while let range = asar.range(of: marker, in: start..<asar.endIndex) {
                start = range.upperBound
                var index = range.upperBound
                while index < asar.endIndex, asar[index] == UInt8(ascii: " ") { index += 1 }
                if let (text, _) = string(at: index), !text.isEmpty { found.insert(text) }
            }
            return found
        }
        let playTexts = keys(of: "Play").reduce(into: Set<String>()) { $0.formUnion(texts(of: $1)) }
        let pauseTexts = keys(of: "Pause").reduce(into: Set<String>()) { $0.formUnion(texts(of: $1)) }
        if !playTexts.isEmpty || !pauseTexts.isEmpty {
            play.formUnion(playTexts)
            pause.formUnion(pauseTexts)
            sources.append("app.asar")
        }
    }
    let found = play.isEmpty && pause.isEmpty ? nil
        : Kept(play: play.sorted(), pause: pause.sorted(), source: sources.joined(separator: ", "))
    cache[key] = .some(found)
    try? files.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    // Whole or not at all: a run stopped mid-write (`_exit`) leaves the old file.
    try? JSONEncoder().encode(cache).write(to: cacheFile, options: .atomic)
    return found.map { (PlayPauseWords(play: Set($0.play), pause: Set($0.pause)), $0.source) }
}

/// The app's own words, for its menu's state and its page's buttons, merged
/// with this tool's list (`playWords`, `pauseWords`). A press reads them
/// whenever it may read the menu or the page (the panel's way reads the
/// page's player bar; kept, they cost a file read).
@MainActor let ownAppWords = pressNeeds([.menu, .page, .panel]) ? appWords(of: appURL) : nil
@MainActor var ownWords: PlayPauseWords? { ownAppWords?.words }

/// Play and Pause as players' pages name their buttons (any case), in
/// English, Spanish, Catalan and a few more, and the app's own words: what
/// this tool looks for and presses until it learns the button, as AutoHush
/// does, by its words changing (`learnPageButton`), in any language.
/// The app's own words join them only for an app whose page comes from its
/// own bundle (Electron, CEF, Flutter): a native app's words name its menu
/// items, and one of them ("Main", Indonesian for Play) would make a page's
/// "Main menu" a Play button. A menu's item is told by them exactly (`menuState`).
@MainActor let playWords = Set(["play", "reproducir", "reprodueix", "reproduir", "lecture", "lire", "wiedergabe",
                                "abspielen", "riproduci", "reproduzir"])
    .union(hiddenInterface == nil ? [] : ownWords?.play.map { $0.lowercased() } ?? [])
@MainActor let pauseWords = Set(["pause", "pausa", "pausar", "posa en pausa", "mettre en pause", "pausieren"])
    .union(hiddenInterface == nil ? [] : ownWords?.pause.map { $0.lowercased() } ?? [])
@MainActor var playPauseWords: Set<String> { playWords.union(pauseWords) }

/// Whether a button's name is one of `words`, alone or first ("Pause
/// current", SoundCloud's player bar; "Play Chill House", a tile, also
/// matches: the bar wins by its slider).
func named(_ label: String, _ words: Set<String>) -> Bool {
    let label = label.lowercased()
    return words.contains { label == $0 || label.hasPrefix($0 + " ") }
}

/// What an element is called: as AutoHush names a web app's button, its
/// description, else its title; else its value (a Flutter app's pressable
/// text keeps its words there).
func label(of element: AXUIElement) -> String {
    [element.text(kAXDescriptionAttribute), element.title, element.text(kAXValueAttribute)].first { !$0.isEmpty } ?? ""
}

/// What a page button's words say of the state: by the learned recipe (the
/// site's own words), else this tool's lists ("Pause" while it plays).
@MainActor func wordSays(_ words: String) -> PlayerState? {
    if let recipe = learned?.recipe ?? savedRecipe, let state = recipe.state(of: PageButton(handle: ButtonHandle(0), label: words)) {
        return state
    }
    return named(words, pauseWords) ? .playing : named(words, playWords) ? .paused : nil
}
