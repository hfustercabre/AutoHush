import AppKit
import CheckedPlayers
import PlayerCheckKit
import AutoHushKit
import MenuPlayers
import WebAppPlayers

// MARK: - The app's own words for Play and Pause

/// The app's own words for Play and Pause, in every language it has, as
/// AutoHush finds them in any app (`PlayPauseWords.found`). Read once per
/// copy and version (kept in words.json, in --caches' folder); nil when
/// none show.
func appWords(of url: URL) -> (words: PlayPauseWords, source: String)? {
    struct Kept: Codable { var play: [String]; var pause: [String]; var source: String }
    let files = FileManager.default
    let cacheFile = cachesFolder.appendingPathComponent("words.json")
    let key = "\(url.path)#\(Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")"
    var cache = (try? JSONDecoder().decode([String: Kept?].self, from: Data(contentsOf: cacheFile))) ?? [:]
    if let kept = cache[key] {
        return kept.map { (PlayPauseWords(play: Set($0.play), pause: Set($0.pause)), $0.source) }
    }
    let found = PlayPauseWords.found(inAppAt: url).map { Kept(play: $0.words.play.sorted(), pause: $0.words.pause.sorted(), source: $0.source) }
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
@MainActor let playWords = Set(PlayPauseWords.common.play.map { $0.lowercased() })
    .union(hiddenInterface == nil ? [] : ownWords?.play.map { $0.lowercased() } ?? [])
@MainActor let pauseWords = Set(PlayPauseWords.common.pause.map { $0.lowercased() })
    .union(hiddenInterface == nil ? [] : ownWords?.pause.map { $0.lowercased() } ?? [])
@MainActor var playPauseWords: Set<String> { playWords.union(pauseWords) }

/// Whether a button's name is one of `words`, alone or first ("Pause
/// current", a web app's player bar; "Play Chill House", a tile, also
/// matches: the bar wins by its slider).
func named(_ label: String, _ words: Set<String>) -> Bool {
    let label = label.lowercased()
    return words.contains { label == $0 || label.hasPrefix($0 + " ") }
}

/// What an element is called, as AutoHush names a page's button
/// (`AccessibilityWebPage.label`): its description, else its title; a
/// Flutter app's item, else its value (a pressable text keeps its words there).
func label(of element: AXUIElement) -> String { AccessibilityWebPage.label(of: element, access: pageAccess) }

/// A button's or a menu item's label as the log shows it: its Play or Pause
/// word only (`PrivateText.label`), from this tool's lists, the app's own
/// words and the site's learned ones; never what it plays.
@MainActor func shown(_ label: String) -> String {
    let learnedWords = [learned?.recipe, savedRecipe].compactMap { $0 }.flatMap { [$0.playLabel, $0.pauseLabel] }
        .filter { !$0.contains(" ") }
    let own = (ownWords?.play ?? []).union(ownWords?.pause ?? [])
    return PrivateText.label(label, words: playPauseWords.union(own).union(learnedWords))
}

/// What a page button's words say of the state: by the learned recipe (the
/// site's own words), else this tool's lists ("Pause" while it plays).
@MainActor func wordSays(_ words: String) -> PlayerState? {
    if let recipe = learned?.recipe ?? savedRecipe, let state = recipe.state(of: PageButton(handle: ButtonHandle(0), label: words)) {
        return state
    }
    return named(words, pauseWords) ? .playing : named(words, playWords) ? .paused : nil
}
