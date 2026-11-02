import Foundation

/// A running snooze's time left as the menu's bar says it: the duration
/// written as the Mac's region writes it ("12 min" in English, which a
/// runner in another region doesn't), then "left", the tests' English.
enum SnoozeTimeLeft {
    static func text(minutes: Int) -> String {
        "\(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) left"
    }
}
