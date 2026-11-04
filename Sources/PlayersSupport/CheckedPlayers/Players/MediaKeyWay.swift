import AppKit
import AutoHushKit
import WebAppPlayers

/// An added app's backup by the keyboard's Play/Pause key (the user,
/// 2026-11-04), which macOS sends to the app it counts as Now Playing, not
/// to one AutoHush picks: pressed only while macOS says this app holds Now
/// Playing (its process or one of its helpers), never when it can't tell,
/// and only from the opposite state, as the app's surest signs tell it
/// (`state`, its `sureState`), read again just before it's posted; not
/// pressed (`NotPressed`), the next way is tried. A toggle, it's pressed
/// once and checked by those signs (`PressCheck.toggleWait`), never again:
/// a second press would undo a first the app is only slow to show.
/// No check tests it, so it's tried after the ways that worked
/// (`WayOrder`). Posting the key needs Accessibility, which every added
/// app's ways but its AppleScript need anyway.
struct MediaKeyWay: FadelessMusicPlayer, PolledMusicPlayer {
    /// It wasn't pressed, so nothing changed: the next way is tried, as for
    /// one passed over (`CheckedPlayer+Backups`).
    struct NotPressed: Error, CustomStringConvertible {
        let description: String
    }

    let bundleID: String
    let name: String
    private let processIdentifier: @Sendable () -> pid_t?
    /// The app's state by its surest signs, set by its player.
    let state: LateState
    /// Which app is Now Playing (blocks: a fresh copy of AutoHush answers).
    private let nowPlaying: @Sendable () async -> NowPlayingApp.Answer
    private let pressKey: @Sendable () async -> Void
    private let sleep: VolumeFader.Sleep

    init(bundleID: String, name: String, state: LateState = LateState(), processIdentifier: (@Sendable () -> pid_t?)? = nil,
         nowPlaying: @escaping @Sendable () async -> NowPlayingApp.Answer = { await MediaKeyWay.queue.run { NowPlayingApp.current() } },
         pressKey: @escaping @Sendable () async -> Void = { await MainActor.run { PlayPauseKey.press() } },
         sleep: @escaping VolumeFader.Sleep = { try? await Task.sleep(for: .seconds($0)) }) {
        self.bundleID = bundleID
        self.name = name
        self.processIdentifier = processIdentifier ?? { NSRunningApplication.running(bundleID)?.processIdentifier }
        self.state = state
        self.nowPlaying = nowPlaying
        self.pressKey = pressKey
        self.sleep = sleep
    }

    var controlPermission: Permission { .accessibility(player: name) }

    /// It judges its own press, by the app's signs.
    var checksItsPresses: Bool { true }

    /// It tells nothing of its own: the app's signs do.
    func playerState() async -> PlayerState { .unknown }

    func statesItself() async -> Bool { false }

    func verifyControlAccess() async throws {}

    func pause() async throws { try await press(to: .paused) }

    func play() async throws { try await press(to: .playing) }

    private func press(to target: PlayerState) async throws {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        guard try Self.needsPress(from: await state.state(), to: target) else { return }
        let answer = await nowPlaying()
        guard case .process(let holder) = answer, ProcessResponsibility.isOwned(holder, by: pid) else {
            let why = switch answer {
            case .process(let holder): "another app is Now Playing (pid \(holder))"
            case .none: "no app is Now Playing"
            case .unknown: "macOS doesn’t say which app is Now Playing"
            }
            throw NotPressed(description: why)
        }
        // Read again: asking Now Playing takes up to 2 s, and a press of the
        // way before, late, may have shown meanwhile.
        guard try Self.needsPress(from: await state.state(), to: target) else { return }
        try await PressCheck(name: "\(name) (the Play/Pause key)", isToggle: true, press: { [pressKey] _ in await pressKey() },
                             state: { [state] in await state.state() }, sleep: sleep).press(to: target)
    }

    /// Whether the key would take it from `state` to `target`: `false` when
    /// it's there already (stopped counts as paused); `NotPressed` when its
    /// state can't be told, or it has nothing to play.
    private static func needsPress(from state: PlayerState, to target: PlayerState) throws -> Bool {
        switch state {
        case .playing: return target == .paused
        case .paused: return target == .playing
        case .stopped:
            if target == .paused { return false }
            throw NotPressed(description: "it has nothing to play")
        case .unknown: throw NotPressed(description: "its state can’t be told")
        case .notRunning: throw MusicPlayerError.playerNotRunning
        }
    }

    /// Asked on its own queue, never on Swift's shared threads: the answer
    /// comes from another process, in up to 2 s.
    static let queue = DispatchQueue(label: "AutoHush.CheckedPlayer.nowPlaying", qos: .userInitiated)
}
