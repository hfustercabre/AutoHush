import AutoHushTestSupport
import CheckedPlayers

/// The menu bar's Now Playing setting, in memory instead of Control
/// Center's: 24 (hidden by the user) unless a test says otherwise.
package final class NowPlayingSettingInMemory: Sendable {
    private let stored: Locked<Int?>

    package init(_ value: Int? = 24) {
        stored = Locked(value)
    }

    package var value: Int? {
        get { stored.value }
        set { stored.value = newValue }
    }

    package var setting: NowPlayingSetting.Setting {
        NowPlayingSetting.Setting(read: { self.value }, write: { self.stored.value = $0 })
    }
}
