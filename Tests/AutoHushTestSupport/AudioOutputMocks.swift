import CoreAudio
import Foundation
import AutoHushKit

// Stand-ins for the Mac's outputs: their mutes (Add an App's check) and
// their volume (Level the volume). Shared by the engine's tests and the
// app's (AppDelegate), so no test mutes or turns down the machine it runs on.

/// Outputs and their mutes, in memory: sound plays through 7 (the built-in
/// speakers); 9 (a USB DAC) has no mute control unless a test gives it one.
package final class MockOutputMuting: OutputMuting, @unchecked Sendable {
    private let lock = NSLock()
    private var _current: AudioObjectID? = 7
    private var _uids: [AudioObjectID: String] = [7: "BuiltInSpeaker", 9: "USBDAC"]
    private var _mutes: [AudioObjectID: Bool] = [7: false]
    /// Who listens to each output's mute, by a number of their own.
    private var listeners: [AudioObjectID: [Int: @Sendable () -> Void]] = [:]
    /// Who listens to sound moving to another output.
    private var followers: [Int: @Sendable () -> Void] = [:]
    private var nextListener = 0

    package init() {}

    package var current: AudioObjectID? {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }

    /// Each output's UID; one without is unplugged.
    package var uids: [AudioObjectID: String] {
        get { lock.withLock { _uids } }
        set { lock.withLock { _uids = newValue } }
    }

    /// Each output's mute (`nil`: it has no mute control).
    package var mutes: [AudioObjectID: Bool] {
        get { lock.withLock { _mutes } }
        set { lock.withLock { _mutes = newValue } }
    }

    /// How many listen to the output's mute now.
    package func listenerCount(_ device: AudioObjectID) -> Int {
        lock.withLock { listeners[device]?.count ?? 0 }
    }

    /// How many listen to sound moving to another output now.
    package var followerCount: Int { lock.withLock { followers.count } }

    /// Sound moves to `device` (headphones plugged in, another output
    /// chosen): those who listen hear of it.
    package func soundMoves(to device: AudioObjectID?) {
        current = device
        for follower in lock.withLock({ Array(followers.values) }) { follower() }
    }

    /// The user presses the mute key: the output's mute changes, and its
    /// listeners hear of it.
    package func user(muted: Bool, _ device: AudioObjectID) {
        setMuted(muted, device)
        notify(device)
    }

    /// The output's listeners hear of a change (Core Audio's come later, on
    /// a queue of their own).
    package func notify(_ device: AudioObjectID) {
        for listener in lock.withLock({ Array((listeners[device] ?? [:]).values) }) { listener() }
    }

    package func defaultOutput() -> AudioObjectID? { current }
    package func isMuted(_ device: AudioObjectID) -> Bool? { lock.withLock { _uids[device] == nil ? nil : _mutes[device] } }
    package func setMuted(_ muted: Bool, _ device: AudioObjectID) {
        lock.withLock { if _mutes[device] != nil { _mutes[device] = muted } }
    }
    package func uid(of device: AudioObjectID) -> String? { lock.withLock { _uids[device] } }
    package func device(withUID uid: String) -> AudioObjectID? { lock.withLock { _uids.first { $0.value == uid }?.key } }

    package func observeMute(of device: AudioObjectID, _ onChange: @escaping @Sendable () -> Void) -> AnyObject? {
        let number = lock.withLock {
            nextListener += 1
            listeners[device, default: [:]][nextListener] = onChange
            return nextListener
        }
        return Listening { [weak self] in self?.lock.withLock { _ = self?.listeners[device]?.removeValue(forKey: number) } }
    }

    package func observeDefaultOutput(_ onChange: @escaping @Sendable () -> Void) -> AnyObject? {
        let number = lock.withLock {
            nextListener += 1
            followers[nextListener] = onChange
            return nextListener
        }
        return Listening { [weak self] in self?.lock.withLock { _ = self?.followers.removeValue(forKey: number) } }
    }

    /// Listens until it's let go.
    private final class Listening {
        let stop: () -> Void
        init(stop: @escaping () -> Void) { self.stop = stop }
        deinit { stop() }
    }
}

/// An output whose volume is per channel (or main), or none, in memory:
/// sound plays through 42 ("Speakers"), unless it's unplugged.
package final class MockSystemVolume: SystemVolumeControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var _decibels: [AudioObjectPropertyElement: Float]?
    private var _sets: [[AudioObjectPropertyElement: Float]] = []
    private var _isPlugged = true
    package let lowest: Float

    package init(_ decibels: [AudioObjectPropertyElement: Float]?, lowest: Float = -60) {
        _decibels = decibels
        self.lowest = lowest
    }

    package var decibels: [AudioObjectPropertyElement: Float]? {
        get { lock.withLock { _decibels } }
        set { lock.withLock { _decibels = newValue } }
    }

    /// Each volume set, in turn.
    package var sets: [[AudioObjectPropertyElement: Float]] { lock.withLock { _sets } }

    package var isPlugged: Bool {
        get { lock.withLock { _isPlugged } }
        set { lock.withLock { _isPlugged = newValue } }
    }

    package func defaultOutput() -> AudioObjectID? { isPlugged ? 42 : nil }
    package func uid(of device: AudioObjectID) -> String? { device == 42 && isPlugged ? "Speakers" : nil }
    package func device(withUID uid: String) -> AudioObjectID? { uid == "Speakers" && isPlugged ? 42 : nil }

    package func volume(of device: AudioObjectID) -> SystemVolume? {
        guard device == 42, isPlugged else { return nil }
        return decibels.map { SystemVolume(decibels: $0, lowest: lowest) }
    }

    package func setDecibels(_ decibels: [AudioObjectPropertyElement: Float], of device: AudioObjectID) {
        lock.withLock {
            _decibels = decibels
            _sets.append(decibels)
        }
    }
}
