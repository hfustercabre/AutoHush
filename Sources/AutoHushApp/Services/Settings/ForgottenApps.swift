import AutoHushKit

/// Apps removed from Settings → Sound Sources (`UserSettings.forget`), as
/// they were, so Undo can put them back (`UserSettings.remember`).
struct ForgottenApps: Equatable {
    /// An app that had played: its place in line then, 0 played last.
    struct Seen: Equatable {
        let place: Int
        let app: AudioSource
    }

    /// The apps removed, as asked.
    let apps: [AudioSource]
    /// Those that had played, by their place in line.
    let seen: [Seen]
    /// Those that were ignored.
    let ignored: [AudioSource]
}
