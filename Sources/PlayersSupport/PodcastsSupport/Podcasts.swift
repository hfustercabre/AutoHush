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
