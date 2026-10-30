import AutoHushKit
import Foundation

/// The pages a Chromium browser plays now: it holds one "Playing audio"
/// assertion per playing page, all on its own process (Chrome and Brave,
/// measured: a web app, a tab's file, a Web Audio tone, a call, a tab in
/// another profile each added one). A Chromium web app plays through its
/// browser, so this, against the count of its browser's other pages, is
/// what tells whether the web app itself plays (Player Check's sign).
package enum PlayingPages {
    package static func count(ofBrowser pid: pid_t) -> Int {
        count(in: IOKitPowerAssertionReader.rawAssertionsByProcess()[NSNumber(value: pid)] ?? [])
    }

    /// The "Playing audio" assertions the process holds itself.
    static func count(in assertions: [[String: Any]]) -> Int {
        assertions.filter { $0["AssertionOnBehalfOfPID"] == nil && $0["AssertName"] as? String == "Playing audio" }.count
    }

    /// Whether the web app plays, from its browser's playing pages `total`
    /// and its other pages `others` (counted while the web app's state was
    /// known): one more, it plays; as many, it doesn't (its own goes about 3 s
    /// after it pauses); else `nil`, another page started or stopped.
    package static func webAppPlays(total: Int, others: Int) -> Bool? {
        total == others + 1 ? true : total == others ? false : nil
    }
}
