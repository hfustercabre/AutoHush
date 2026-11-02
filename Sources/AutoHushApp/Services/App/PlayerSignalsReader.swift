import AppKit
import AutoHushKit

/// Reads `PlayerSignals` for the welcome window, as AutoHush already reads
/// them elsewhere: the apps open from NSWorkspace, their sound from Core
/// Audio's process list (no permission asked), and Now Playing from
/// `NowPlayingApp`. Tests replace it.
struct PlayerSignalsReader: Sendable {
    /// The apps among these bundle IDs that are open, with their process
    /// IDs: quick, on the main actor.
    var open: @MainActor @Sendable ([String]) -> [String: pid_t]
    /// Those of the open apps playing sound or in Now Playing: off the main
    /// actor, up to 2 seconds (Now Playing's answer).
    var playing: @Sendable ([String: pid_t]) async -> Set<String>

    static let live = PlayerSignalsReader(
        open: { ids in
            Dictionary(ids.compactMap { id in NSRunningApplication.running(id).map { (id, $0.processIdentifier) } },
                       uniquingKeysWith: { first, _ in first })
        },
        playing: { open in
            guard !open.isEmpty else { return [] }
            return await PlayerSignalsReader.queue.run(qos: .userInitiated) {
                let sound = OwnedAudioProcesses()
                var playing = Set(open.filter { sound.isPlayingSound(appPID: $0.value) }.keys)
                if case .process(let pid) = NowPlayingApp.current(), let id = open.first(where: { $0.value == pid })?.key {
                    playing.insert(id)
                }
                return playing
            }
        }
    )

    /// Reads nothing: no app open, none playing.
    static let none = PlayerSignalsReader(open: { _ in [:] }, playing: { _ in [] })

    /// Core Audio's reads and Now Playing's answer block: done here, off
    /// Swift's shared threads.
    private static let queue = DispatchQueue(label: "AutoHush.PlayerSignals", qos: .utility)
}
