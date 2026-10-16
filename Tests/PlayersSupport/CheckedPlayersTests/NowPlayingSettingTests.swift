import Foundation
import Testing
@testable import CheckedPlayers

@Suite("NowPlayingSetting")
struct NowPlayingSettingTests {
    /// The setting as a test holds it, instead of Control Center's.
    private final class Held: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Int?
        init(_ value: Int?) { stored = value }
        var value: Int? {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
        var setting: NowPlayingSetting.Setting { .init(read: { self.value }, write: { self.value = $0 }) }
    }

    /// Defaults in a suite of their own, removed after.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "AutoHush.NowPlayingSettingTests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        body(UserDefaults(suiteName: suite)!)
    }

    @Test("shown for a press, then put back, unless the user changed it meanwhile; the record goes either way")
    func whileShown() {
        withDefaults { defaults in
            let held = Held(24)
            #expect(NowPlayingSetting.whileShown(defaults: defaults, setting: held.setting, until: { true }) { held.value } == 16)
            #expect(held.value == 24)
            _ = NowPlayingSetting.whileShown(defaults: defaults, setting: held.setting, until: { true }) { held.value = 2 }
            #expect(held.value == 2)
            #expect(defaults.object(forKey: NowPlayingSetting.leftKey) == nil)
            // Not hidden: nothing to show.
            #expect(NowPlayingSetting.whileShown(defaults: defaults, setting: held.setting, until: { true }) { 1 } == nil)
        }
    }

    /// A record left: its process (nil: a bare value, kept before its
    /// process was), the setting now, the setting after, whether it stays.
    static let left: [(pid: Int?, now: Int, after: Int, kept: Bool)] = [
        (Int(getpid()), 16, 24, false), // this process's: it's quitting or stopping during its press
        (Int(Int32.max), 16, 24, false), // a process gone: it crashed during its press
        (nil, 16, 24, false),
        (1, 16, 16, true), // another process's press under way (launchd stands for it)
        (Int(Int32.max), 2, 2, false), // changed in System Settings since: left as it is
    ]

    @Test("a press left shown is put back when it was this process's or its process is gone, only while still shown", arguments: left)
    func restoreIfLeft(pid: Int?, now: Int, after: Int, kept: Bool) {
        withDefaults { defaults in
            let held = Held(now)
            if let pid {
                defaults.set(["value": 24, "pid": pid], forKey: NowPlayingSetting.leftKey)
            } else {
                defaults.set(24, forKey: NowPlayingSetting.leftKey)
            }
            NowPlayingSetting.restoreIfLeft(defaults: defaults, setting: held.setting)
            #expect(held.value == after)
            #expect((defaults.object(forKey: NowPlayingSetting.leftKey) != nil) == kept)
        }
    }
}
