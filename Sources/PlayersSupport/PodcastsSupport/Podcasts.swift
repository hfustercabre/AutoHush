import Foundation
import AutoHushKit
import MenuPlayers

extension MenuPlayerProfile {
    /// Apple Podcasts, the Podcasts app that comes with macOS. It can't be
    /// scripted, so AutoHush presses Play/Pause in its Controls menu.
    package static let applePodcasts = MenuPlayerProfile(
        bundleID: "com.apple.podcasts",
        name: "Apple Podcasts",
        menuName: "Controls",
        readWords: PodcastsWords.read(fromAppAt:),
        iconPlaceholder: .applePodcasts
    )
}

/// Apple Podcasts' words for Play and Pause, from its translation table
/// (`Localizable.loctable`, every language in one property list): in each
/// language, the texts whose English is "Play" or "Pause".
enum PodcastsWords {
    /// The words of the Podcasts app at `appURL`; `nil` when they can't be read.
    static func read(fromAppAt appURL: URL) -> PlayPauseWords? {
        let table = appURL.appending(path: "Contents/Resources/Localizable.loctable")
        guard let data = try? Data(contentsOf: table, options: .alwaysMapped) else { return nil }
        return find(in: data)
    }

    /// The words in a translation table: `[language: [key: text]]`.
    static func find(in data: Data) -> PlayPauseWords? {
        guard let languages = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        else { return nil }
        let tables = languages.compactMapValues { ($0 as? [String: Any])?.compactMapValues { $0 as? String } }
        guard let english = tables["en"] else { return nil }
        func words(_ text: String) -> Set<String> {
            let keys = english.filter { $0.value == text }.keys
            return Set(tables.values.flatMap { table in keys.compactMap { table[$0] } })
        }
        return PlayPauseWords(play: words("Play"), pause: words("Pause"))
    }
}
