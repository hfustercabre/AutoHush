/// AutoHush's menu bar icon: sound bars cut out of a rounded square.
///
/// Every state uses the same tile; only the bars change, and they stand on
/// one baseline, so a change of state looks like the same bars moving. The
/// icon is drawn in code (no image files) and used as a template image: macOS
/// tints it for light and dark menu bars and dims it while auto-pause is off.
enum MenuBarIcon: CaseIterable, Sendable {
    /// Sound bars: music is playing and AutoHush is listening.
    case playing
    /// A silent dot, then the bars held as a pause sign: AutoHush paused the
    /// music for another app.
    case pausedForApp
    /// Three dots on the baseline: no music is playing.
    case noMusic
    /// Two bars and an arrow out: the music plays on another device.
    case elsewhere
    /// Hollow bars: AutoHush is starting.
    case starting
    /// Bars and an exclamation mark: something needs the user's attention.
    case attention
}
