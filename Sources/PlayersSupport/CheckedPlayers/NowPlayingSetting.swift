import ApplicationServices
import Foundation

/// The menu bar's Now Playing setting (System Settings → Menu Bar; Control
/// Center before macOS 26): Control Center's `NowPlaying` for this Mac
/// (current host), flags: 8 hides it (8, 24), 2 or 16 show it (2, 16, 18;
/// measured on macOS 27, 2026-10-16: System Settings' "Don't Show" stored
/// 24 on the user's Mac, 18 once shown again). Written here, it's shown
/// within 0.1 s and hidden again within 0.9 s, without restarting Control
/// Center. Hidden by the user, Now Playing is shown only for the moment of a
/// press through its panel, then hidden again (the user, 2026-10-16), and
/// the value to put back is kept until it is, so a quit or a crash meanwhile
/// is put right at the next start (`restoreIfLeft`).
package enum NowPlayingSetting {
    /// The flag that hides it.
    static let hiddenFlag = 8
    static let shownWhenActive = 16
    private static let domain = "com.apple.controlcenter"
    private static let key = "NowPlaying"
    /// Where the value to put back is kept meanwhile (this process's defaults).
    static let leftKey = "nowPlayingShownForAPress"

    static func read() -> Int? {
        CFPreferencesCopyValue(key as CFString, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int
    }

    static func write(_ value: Int) {
        CFPreferencesSetValue(key as CFString, value as CFNumber, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    /// Whether the user hid Now Playing from the menu bar.
    package static var isHidden: Bool { read().map { $0 & hiddenFlag != 0 } ?? false }

    /// Runs `body` with Now Playing shown in the menu bar, when the user hid
    /// it (and its item shows within a second), then hides it again; `nil`
    /// when it wasn't hidden or didn't show.
    package static func whileShown<T>(defaults: UserDefaults = .standard, until shown: () -> Bool, _ body: () -> T) -> T? {
        guard let original = read(), original & hiddenFlag != 0 else { return nil }
        defaults.set(original, forKey: leftKey)
        write(shownWhenActive)
        defer {
            write(original)
            defaults.removeObject(forKey: leftKey)
        }
        let deadline = Date().addingTimeInterval(1)
        while !shown() {
            guard Date() < deadline else { return nil }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return body()
    }

    /// Puts back a setting this process changed and didn't put back (it quit
    /// or crashed during a press).
    package static func restoreIfLeft(defaults: UserDefaults = .standard) {
        guard let value = defaults.object(forKey: leftKey) as? Int else { return }
        write(value)
        defaults.removeObject(forKey: leftKey)
    }
}
