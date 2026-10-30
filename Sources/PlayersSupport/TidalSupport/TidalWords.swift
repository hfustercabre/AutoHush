import Foundation
import MenuPlayers

/// TIDAL's words for Play and Pause: every "t-play" and "t-pause" text in its
/// translation tables, which are inside its app bundle (`app.asar`).
enum TidalWords {
    /// Every "t-play" and "t-pause" text in `data`.
    static func find(in data: Data) -> PlayPauseWords {
        PlayPauseWords(play: PlayPauseWords.asarTexts(ofKey: "t-play", in: data), pause: PlayPauseWords.asarTexts(ofKey: "t-pause", in: data))
    }

    /// The words of the TIDAL at `appURL`; `nil` when they can't be read.
    static func read(fromAppAt appURL: URL) -> PlayPauseWords? {
        let asar = appURL.appending(path: "Contents/Resources/app.asar")
        guard let data = try? Data(contentsOf: asar, options: .alwaysMapped) else { return nil }
        return find(in: data)
    }
}
