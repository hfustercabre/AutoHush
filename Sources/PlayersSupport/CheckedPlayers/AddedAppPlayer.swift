import AppKit
import AutoHushKit

/// An app added with Add an App, as a player: pressed by the way its check
/// found (`CheckedPlayer`), or muted instead of paused (`MutedApp`), a type
/// each (X18, the full check, 2026-10-19: one type branched on muting in 12
/// places). `CheckedPlayers` makes the one its setup asks for.
package protocol AddedAppPlayer: Actor, MutingMusicPlayer {
    /// What its check found, as kept.
    nonisolated var setup: PlayerSetup { get }
}

extension AddedAppPlayer {
    package nonisolated var bundleID: String { setup.bundleID }
    package nonisolated var name: String { setup.name }
    /// Where it was checked, else where Launch Services finds it (moved
    /// since); `nil` while it isn't installed.
    package nonisolated var installedURL: URL? {
        if FileManager.default.fileExists(atPath: setup.appURL.path) { return setup.appURL }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: setup.bundleID)
    }
    package nonisolated var kind: MusicPlayerKind { .checkedApp }
    /// Its presses are checked by it (`PressCheck` doesn't check them
    /// again), and a mute always takes.
    package nonisolated var checksItsPresses: Bool { true }
}

/// What an added app's keep-awake assertions say, by AntiDot mode's rule
/// (`AnnouncedAssertions.announcing`, its names learned while its sound is
/// on; one keeping only the display awake doesn't tell, unless it's one of
/// its video names): playing while it announces, paused once it has
/// before; `.unknown` until it has.
struct PlaybackAssertions: Sendable {
    /// What the app's own processes hold now.
    static let read: @Sendable (pid_t) -> Set<PowerAssertion> = { IOKitPowerAssertionReader().assertions(ownedBy: $0) }

    private let read: @Sendable (pid_t) -> Set<PowerAssertion>
    private var announced = AnnouncedAssertions()
    private var seen = false

    init(read: @escaping @Sendable (pid_t) -> Set<PowerAssertion>) {
        self.read = read
    }

    /// `soundOn`: whether its sound output is on, asked only while it holds one.
    mutating func state(of pid: pid_t, soundOn: () -> Bool) -> PlayerState {
        let held = read(pid)
        if !held.isEmpty, soundOn() { announced.learn(held) }
        if announced.announcing(held) {
            seen = true
            return .playing
        }
        return seen ? .paused : .unknown
    }
}
