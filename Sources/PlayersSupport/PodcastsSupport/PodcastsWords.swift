import Foundation
import MenuPlayers

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
        guard let tables = PlayPauseWords.loctable(data), let english = tables["en"] else { return nil }
        return PlayPauseWords.tableWords(tables.values, english: english)
    }
}
