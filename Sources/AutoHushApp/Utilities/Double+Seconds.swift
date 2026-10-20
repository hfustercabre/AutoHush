import Foundation

extension Double {
    /// These seconds as Settings and Diagnostics show a timing: "0.5 s",
    /// "2 s", up to two decimals, in the user's language.
    var secondsText: String {
        let number = formatted(.number.precision(.fractionLength(0...2)))
        return String(localized: "\(number) s", comment: "A duration in seconds")
    }

    /// These seconds as a countdown shows the time left: "1:45", rounded
    /// up, never below 0:00.
    var countdownText: String {
        Duration.seconds(Swift.max(0, Int(rounded(.up)))).formatted(.time(pattern: .minuteSecond))
    }
}
