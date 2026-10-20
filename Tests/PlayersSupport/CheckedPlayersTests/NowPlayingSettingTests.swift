import Foundation
import Testing
import AutoHushTestSupport
import PlayersTestSupport
@testable import CheckedPlayers

@Suite("NowPlayingSetting")
struct NowPlayingSettingTests {
    /// Defaults in a suite of their own, removed after.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = TestDefaults("AutoHush.NowPlayingSettingTests")
        defer { suite.remove() }
        body(suite.defaults)
    }

    @Test("hidden by its flag 8 (8, 24), shown by any other value (2, 16, 18) or never set", arguments: [
        (8, true), (24, true), (2, false), (16, false), (18, false), (nil, false),
    ] as [(Int?, Bool)])
    func hiddenFlag(value: Int?, hidden: Bool) {
        #expect(NowPlayingSetting.isHidden(value) == hidden)
    }

    @Test("shown for a press, then put back, unless the user changed it meanwhile; not shown within a second, no press; the record goes either way")
    func whileShown() {
        withDefaults { defaults in
            let held = NowPlayingSettingInMemory(24)
            #expect(NowPlayingSetting.whileShown(defaults: defaults, setting: held.setting, until: { true }) { held.value } == 16)
            #expect(held.value == 24)
            _ = NowPlayingSetting.whileShown(defaults: defaults, setting: held.setting, until: { true }) { held.value = 2 }
            #expect(held.value == 2)
            #expect(defaults.object(forKey: NowPlayingSetting.leftKey) == nil)
            // Not hidden: nothing to show.
            #expect(NowPlayingSetting.whileShown(defaults: defaults, setting: held.setting, until: { true }) { 1 } == nil)
            // Its item never shows: no press, and hidden again.
            held.value = 24
            #expect(NowPlayingSetting.whileShown(defaults: defaults, setting: held.setting, until: { false }) { 1 } == nil)
            #expect(held.value == 24)
            #expect(defaults.object(forKey: NowPlayingSetting.leftKey) == nil)
        }
    }

    /// A record left: its process (nil: a bare value, kept before its
    /// process was), the value it keeps, the setting now, the setting after,
    /// whether it stays.
    static let left: [(pid: Int?, value: Int?, now: Int, after: Int, kept: Bool)] = [
        (Int(getpid()), 24, 16, 24, false), // this process's: it's quitting or stopping during its press
        (Int(Int32.max), 24, 16, 24, false), // a process gone: it crashed during its press
        (nil, 24, 16, 24, false),
        (1, 24, 16, 16, true), // another process's press under way (launchd stands for it)
        (Int(Int32.max), 24, 2, 2, false), // changed in System Settings since: left as it is
        (Int(Int32.max), nil, 16, 16, false), // nothing to put back: the record only goes
    ]

    @Test("a press left shown is put back when it was this process's or its process is gone, only while still shown; a record with nothing to put back goes", arguments: left)
    func restoreIfLeft(pid: Int?, value: Int?, now: Int, after: Int, kept: Bool) {
        withDefaults { defaults in
            let held = NowPlayingSettingInMemory(now)
            if let pid {
                var record = ["pid": pid]
                record["value"] = value
                defaults.set(record, forKey: NowPlayingSetting.leftKey)
            } else {
                defaults.set(value, forKey: NowPlayingSetting.leftKey)
            }
            NowPlayingSetting.restoreIfLeft(defaults: defaults, setting: held.setting)
            #expect(held.value == after)
            #expect((defaults.object(forKey: NowPlayingSetting.leftKey) != nil) == kept)
        }
    }
}
