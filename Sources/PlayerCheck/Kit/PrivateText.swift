import Foundation

/// What the check's log and report never hold (the user, 2026-10-15: "Make
/// the log leave both out"): the Mac account's name, in its home folder's
/// path, which is written `~`; and what was playing, in a page's buttons
/// (a playlist's, a song's, an album's name), the Now Playing panel's rows,
/// window titles and what an app plays by AppleScript. A button is named by
/// its Play or Pause word only, a row by where it is and what told it.
package enum PrivateText {
    /// `line` with the home folder written `~`, wherever a path holds it.
    package static func redacted(_ line: String, home: String = NSHomeDirectory()) -> String {
        guard home.count > 1 else { return line }
        return line.replacingOccurrences(of: home, with: "~")
    }

    /// A button's (or a menu item's) label as the log may show it, quoted:
    /// whole when it's one of `words` (Play and Pause in the lists, the
    /// site's own one-word ones), else its first word when that's one, then
    /// "…"; else only how many words it has.
    package static func label(_ label: String, words: Set<String>) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "a button with no name" }
        let lowered = Set(words.map { $0.lowercased() })
        if lowered.contains(trimmed.lowercased()) { return "“\(trimmed)”" }
        let parts = trimmed.split(separator: " ")
        if let first = parts.first, lowered.contains(first.lowercased()) { return "“\(first) …”" }
        return parts.count == 1 ? "a one-word name" : "a name of \(parts.count) words"
    }

    /// A Now Playing panel row, as the log may show it: its place among the
    /// rows, and what told it was the app's (`why`, e.g. "its song found in
    /// its window's title"), never its text.
    package static func row(_ index: Int, of count: Int, why: String?) -> String {
        "row \(index + 1) of \(count)" + (why.map { ", \($0)" } ?? "")
    }
}
