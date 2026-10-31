import Foundation

// One of playercheck's one-line answers, a tab between fields: the helper
// writes it with its `line`, and AutoHush and the Player Check app read it
// with its `init?(line:)`, so neither side can drift.

/// Why an app can be in Now Playing, a line of --now-playing-reasons:
/// "<path>\t<reason>\t<interface>\t<switches>\t<kind>\t<browser>", each
/// empty when none.
package struct NowPlayingReasonsLine: Equatable, Sendable {
    /// The kind of interface `interface` names, for whoever reads the line
    /// (its name is for people).
    package enum InterfaceKind: String, Sendable {
        case electron, cef, flutter, chromiumWebApp
    }

    package var path: String
    /// What lets it be in Now Playing (`NowPlayingReason`); `nil` when
    /// nothing shows it can.
    package var reason: String?
    /// What hides its interface until a switch is on ("Electron 38.4.0",
    /// "Flutter", "Google Chrome web app"…).
    package var interface: String?
    /// The switches a check turns on for it, in order ("Electron's switch,
    /// else VoiceOver's switch").
    package var switches: String?
    package var kind: InterfaceKind?
    /// A Chromium browser's web app's browser, as its bundle names it
    /// ("Google Chrome").
    package var browser: String?

    package init(path: String, reason: String?, interface: String? = nil, switches: String? = nil, kind: InterfaceKind? = nil,
                 browser: String? = nil) {
        self.path = path
        self.reason = reason
        self.interface = interface
        self.switches = switches
        self.kind = kind
        self.browser = browser
    }

    package var line: String {
        [path, reason ?? "", interface ?? "", switches ?? "", kind?.rawValue ?? "", browser ?? ""].joined(separator: "\t")
    }

    package init?(line: some StringProtocol) {
        let fields = String(line).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 2, !fields[0].isEmpty else { return nil }
        let field = { (index: Int) in index < fields.count && !fields[index].isEmpty ? fields[index] : nil }
        self.init(path: fields[0], reason: field(1), interface: field(2), switches: field(3), kind: field(4).flatMap(InterfaceKind.init),
                  browser: field(5))
    }
}
