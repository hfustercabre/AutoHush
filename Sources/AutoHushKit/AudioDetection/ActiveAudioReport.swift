import Foundation

/// The Diagnostics text: one line per app with its sound on, saying how
/// AutoHush judges it, e.g. "Google Chrome (com.google.Chrome) — playing (-23 dBFS)".
struct ActiveAudioReport {
    /// Apps whose processes have their output open.
    var present: Set<String>
    /// Apps counted as playing (they may have closed their output since).
    var playing: Set<String>
    /// Apps audible in the latest check, playing or about to be.
    var audible: Set<String>
    /// Loudest tapped peak (0…1) per app, when audio levels are measured.
    var levels: [String: Float]
    var ignored: Set<String>
    /// AntiDot mode: apps telling macOS they play now, and apps that did before.
    var announcing: Set<String>
    var announcedBefore: Set<String>
    /// The apps' names; an app without one is shown by its ID.
    var sources: [String: AudioSource]

    var lines: [String] {
        present.union(playing).sorted().map { id in
            let line = "\(label(for: id)) — \(state(of: id))"
            return detail(for: id).map { "\(line) (\($0))" } ?? line
        }
    }

    private func label(for id: String) -> String {
        guard let name = sources[id]?.name, name != id else { return id }
        return "\(name) (\(id))"
    }

    private func state(of id: String) -> String {
        let state = playing.contains(id) ? "playing" : audible.contains(id) ? "starting" : "output open, silent"
        return ignored.contains(id) ? "\(state), ignored" : state
    }

    /// What the judgement rests on: what the app tells macOS, or its level.
    private func detail(for id: String) -> String? {
        if announcing.contains(id) { return "tells macOS it is playing" }
        if announcedBefore.contains(id) { return "not telling macOS it is playing" }
        guard let level = levels[id] else { return nil }
        return level > 0 ? String(format: "%.0f dBFS", 20 * log10(level)) : "silence"
    }
}
