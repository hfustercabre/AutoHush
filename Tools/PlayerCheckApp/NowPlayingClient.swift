import PlayerCheckKit

/// An app mediaremoted keeps in Now Playing now, as `playercheck
/// --now-playing-list` reads it from macOS's log (administrators only): its
/// last state (Playing, Paused, Stopped…), or Registered: ready for Now
/// Playing, never said it plays; Removed, gone (`--since` only).
typealias NowPlayingClient = NowPlayingListLine

extension NowPlayingListLine {
    var summary: String { isActive ? "Now Playing (\(state))" : "In Now Playing: \(state)" }
}
