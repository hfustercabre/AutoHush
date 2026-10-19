import ApplicationServices
import AutoHushKit
import Foundation

/// The menu bar's Now Playing setting (System Settings → Menu Bar; Control
/// Center before macOS 26): Control Center's `NowPlaying` for this Mac
/// (current host), flags: 8 hides it (8, 24), 2 or 16 show it (2, 16, 18;
/// measured on macOS 27, 2026-10-16: System Settings' "Don't Show" stored
/// 24 on the user's Mac, 18 once shown again). Written here, it's shown
/// within 0.1 s and hidden again within 0.9 s, without restarting Control
/// Center. Hidden by the user, Now Playing is shown only for the moment of a
/// press through its panel, then hidden again (the user, 2026-10-16), and
/// the value to put back is kept until it is, with the process that showed
/// it, so a quit or a crash meanwhile is put right at the next start
/// (`restoreIfLeft`).
package enum NowPlayingSetting {
    /// The flag that hides it.
    static let hiddenFlag = 8
    static let shownWhenActive = 16
    private static let domain = "com.apple.controlcenter"
    private static let key = "NowPlaying"
    /// Where the value to put back is kept meanwhile, as "value", with the
    /// process that wrote it as "pid": in the defaults it's given (AutoHush's
    /// own, also for the check run inside AutoHush).
    static let leftKey = "nowPlayingShownForAPress"

    /// The setting, read and written: Control Center's (`controlCenter`);
    /// tests stand in for it.
    package struct Setting: Sendable {
        let read: @Sendable () -> Int?
        let write: @Sendable (Int) -> Void

        package init(read: @escaping @Sendable () -> Int?, write: @escaping @Sendable (Int) -> Void) {
            self.read = read
            self.write = write
        }

        package static let controlCenter = Setting(read: { NowPlayingSetting.read() }, write: { NowPlayingSetting.write($0) })
    }

    static func read() -> Int? {
        // A change made in System Settings since may not be in this process's cache yet.
        CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return CFPreferencesCopyValue(key as CFString, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int
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
    package static func whileShown<T>(defaults: UserDefaults = .standard, setting: Setting = .controlCenter,
                                      until shown: () -> Bool, _ body: () -> T) -> T? {
        guard let original = setting.read(), original & hiddenFlag != 0 else { return nil }
        defaults.set(["value": original, "pid": Int(getpid())], forKey: leftKey)
        setting.write(shownWhenActive)
        defer { putBack(original, defaults: defaults, setting: setting) }
        guard Polling.wait(seconds: 1, every: 0.05, until: shown) else { return nil }
        return body()
    }

    /// Puts back a setting shown for a press and not put back: by this
    /// process (it's quitting or stopping during the press), or by one that
    /// no longer runs (it crashed during one). Another process's press under
    /// way is left to it, as a fresh copy asked for Now Playing during it, or
    /// AutoHush starting while its check presses, would undo it.
    package static func restoreIfLeft(defaults: UserDefaults = .standard, setting: Setting = .controlCenter) {
        guard let left = defaults.object(forKey: leftKey) else { return }
        // A bare value: kept before its process was.
        let record = left as? [String: Any] ?? ["value": left]
        if let pid = (record["pid"] as? Int).flatMap(pid_t.init(exactly:)), pid != getpid(), kill(pid, 0) == 0 || errno == EPERM { return }
        guard let value = record["value"] as? Int else {
            defaults.removeObject(forKey: leftKey)
            return
        }
        putBack(value, defaults: defaults, setting: setting)
    }

    /// Writes `original` back while the setting still holds what was written
    /// for the press; changed since (the user chose in System Settings
    /// meanwhile), it's left as it is. The record goes either way.
    private static func putBack(_ original: Int, defaults: UserDefaults, setting: Setting) {
        if setting.read() == shownWhenActive { setting.write(original) }
        defaults.removeObject(forKey: leftKey)
    }
}
