/// What the app plays, as its windows' titles, its page's player bar and
/// its AppleScript current track or item show it: what tells its row. Only
/// matched, never written in the log.
struct SongTexts {
    var titles: [String] = []
    var bar: [String] = []
    var track: [String] = []
    var all: [String] { titles + bar + track }
}
