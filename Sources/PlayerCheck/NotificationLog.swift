import Foundation
import AutoHushKit
import os
import ScriptablePlayers

// MARK: - State notifications

/// The usual names of a player's state notification: the supported
/// scriptable players' (`<bundle ID>.PlaybackStateChanged`,
/// `<bundle ID>.playerInfo`) and their likely variants. macOS delivers a distributed notification only to
/// observers that name it (one with no name gets nothing, measured on macOS
/// 27), so a name outside this list can't be seen.
let stateNotificationSuffixes = ["PlaybackStateChanged", "playbackStateChanged", "playerInfo", "PlayerInfo",
                                 "PlayerStateChanged", "playerStateChanged", "PlayStateChanged", "playStateChanged"]

/// The state notifications seen, with their userInfo keys, and what each
/// announced: the state in its "Player State", as AutoHush's ScriptablePlayers
/// read it (`PlayerStateObserver`), which is how AutoHush follows such a
/// player instead of asking it. Delivered while the run loop runs; behind a
/// lock rather than the main actor, so where macOS delivers them doesn't matter.
final class NotificationLog: NSObject, Sendable {
    private struct State {
        var seenKeys: [String: Set<String>] = [:]
        /// Each one with a state, in order: its name, the state, when.
        var announcements: [(name: String, state: PlayerState, at: Date)] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    init(bundleID: String) {
        super.init()
        for suffix in stateNotificationSuffixes {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(note(_:)), name: Notification.Name("\(bundleID).\(suffix)"), object: nil,
                suspensionBehavior: .deliverImmediately)
        }
    }
    @objc func note(_ notification: Notification) {
        let keys = (notification.userInfo ?? [:]).keys.map { "\($0)" }
        let said = PlayerStateObserver.playerState(from: notification.userInfo), name = notification.name.rawValue
        state.withLock {
            $0.seenKeys[name, default: []].formUnion(keys)
            if said != .unknown { $0.announcements.append((name, said, Date())) }
        }
    }
    /// The notifications seen, with their userInfo keys.
    var seen: [String: Set<String>] { state.withLock { $0.seenKeys } }
    /// What was announced since `date`, in order.
    func announced(since date: Date) -> [(name: String, state: PlayerState, at: Date)] {
        state.withLock { $0.announcements.filter { $0.at >= date } }
    }
    /// The last state announced since `date`; a player may post each change
    /// twice, the state before, then the new one.
    func lastState(since date: Date) -> PlayerState? { announced(since: date).last?.state }
}

/// The notifications followed through a test.
@MainActor var notifications: NotificationLog?

/// The notification that announced both a trial's pause and its play: what
/// a ScriptablePlayerProfile names (`stateNotification`).
@MainActor var announcingNotification: String?

/// What the notifications announced since `date`, for a trial's line.
@MainActor func announcementLine(since date: Date) -> String? {
    guard let notifications else { return nil }
    let said = notifications.announced(since: date)
    // Silence is worth saying only of an app AutoHush would follow by its notification.
    guard !said.isEmpty else { return scripting?.fitsScriptablePlayer == true ? "    notifications: none announced it" : nil }
    return "    announced: " + said.map { $0.state.rawValue }.joined(separator: ", then ") + " (\(said.last!.name))"
}
