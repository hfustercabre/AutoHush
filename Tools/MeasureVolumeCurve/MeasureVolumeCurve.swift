import AutoHushKit
import AutoHushPlayers
import CoreAudio
import Foundation

/// Measures how a music player turns its volume number (0–100) into loudness,
/// so its `VolumeCurve` can be set and fades sound even.
///
///     swift run measure-volume-curve [bundle-id] [volume …]
///
/// Works with any supported player (default: the first one offered). The
/// player must be running; it plays the music for about 50 seconds at changing
/// volumes, then gets its volume and play state back. Its output is read
/// through AutoHush's own process-tap meter, for loudness only: nothing is
/// recorded or stored. macOS asks once for permission to record system audio
/// (revocable in System Settings → Privacy & Security → Screen & System Audio
/// Recording) and to control the player.
///
/// For each volume it alternates with 100 several times and reports the median
/// level difference in dB, which cancels out the music's own ups and downs.
@main
enum MeasureVolumeCurve {
    static let defaultVolumes = [90, 75, 60, 50, 40, 30, 20, 15, 10, 5, 2, 1]
    static let pairsPerVolume = 4
    static let settle: Duration = .milliseconds(200)  // after a volume change, before measuring
    static let window: Duration = .milliseconds(300)  // measuring time per level

    static func main() async {
        let arguments = CommandLine.arguments.dropFirst()
        let catalog = SupportedPlayers.catalog
        let requested = arguments.dropFirst().compactMap(Int.init)
        let volumes = requested.isEmpty ? defaultVolumes : requested

        let bundleID = arguments.first
        guard let player = bundleID.map({ catalog.player(bundleID: $0) }) ?? catalog.players.first else {
            let supported = catalog.players.map(\.bundleID).joined(separator: ", ")
            fail("\(bundleID ?? "") is not a supported player (supported: \(supported))")
        }
        do {
            try await measure(player, volumes: volumes)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Measures the player at each volume, prints the results and the best
    /// fit, and always gives the player back its volume and play state.
    private static func measure(_ player: any MusicPlayer, volumes: [Int]) async throws {
        try await player.verifyControlAccess()
        guard let originalVolume = await player.volume() else { throw Failure("\(player.name) doesn't report its volume") }
        let wasPlaying = await player.playerState() == .playing
        print("\(player.name): volume \(originalVolume), \(wasPlaying ? "playing" : "not playing")")

        func restore() async {
            try? await player.setVolume(originalVolume)
            if !wasPlaying { try? await player.pause() }
        }

        let results: [(volume: Int, dB: Double)]
        do {
            let meter = try await startMetering(player)
            defer { meter.stopAll() }
            results = try await measureLevels(of: player, at: volumes, with: meter)
        } catch {
            await restore() // never leave the player at a test volume
            throw error
        }
        await restore()
        printFit(results)
    }

    /// Plays the music and taps the player's audio output.
    private static func startMetering(_ player: any MusicPlayer) async throws -> ProcessTapLevelMeter {
        try await player.play()
        try await Task.sleep(for: .seconds(1))
        let processes = HALAudioProcessSnapshotProvider().activeProcesses()
            .filter { $0.bundleID == player.bundleID || $0.bundleID.hasPrefix(player.bundleID + ".") }
        guard !processes.isEmpty else { throw Failure("no audio output from \(player.name); is it playing on this Mac?") }
        let meter = ProcessTapLevelMeter()
        meter.setMeteredProcesses(Set(processes.map(\.objectID)))
        try await Task.sleep(for: .milliseconds(500))
        return meter
    }

    /// Each volume's level relative to volume 100, printed as it is measured.
    private static func measureLevels(
        of player: any MusicPlayer, at volumes: [Int], with meter: ProcessTapLevelMeter
    ) async throws -> [(volume: Int, dB: Double)] {
        guard try await level(of: player, at: 100, with: meter) > 0 else {
            throw Failure("the tap hears silence: allow system audio recording for this tool (or the terminal running it) and try again")
        }
        var results: [(volume: Int, dB: Double)] = []
        for volume in volumes {
            guard let dB = try await relativeLevel(of: player, at: volume, with: meter) else {
                print(String(format: "  volume %3d → no reading (the music was silent)", volume))
                continue
            }
            results.append((volume, dB))
            print(dB.isFinite ? String(format: "  volume %3d → %6.1f dB", volume, dB) : String(format: "  volume %3d → silent", volume))
        }
        return results
    }

    /// The level at `volume` relative to volume 100, in dB: the median of
    /// several back-and-forth readings. `nil` when every reading at 100 was
    /// silent (the music paused or hit a quiet passage).
    private static func relativeLevel(
        of player: any MusicPlayer, at volume: Int, with meter: ProcessTapLevelMeter
    ) async throws -> Double? {
        var differences: [Double] = []
        for _ in 0..<pairsPerVolume {
            let full = try await level(of: player, at: 100, with: meter)
            let reduced = try await level(of: player, at: volume, with: meter)
            if full > 0 { differences.append(reduced > 0 ? 20 * log10(reduced / full) : -.infinity) }
        }
        return differences.isEmpty ? nil : differences.sorted()[differences.count / 2]
    }

    /// The music's average level (RMS, 0…1) at `volume`, once it has settled.
    private static func level(
        of player: any MusicPlayer, at volume: Int, with meter: ProcessTapLevelMeter
    ) async throws -> Double {
        try await player.setVolume(volume)
        try await Task.sleep(for: settle)
        _ = meter.drainLevels()
        try await Task.sleep(for: window)
        return Double(meter.drainLevels().values.map(\.rms).max() ?? 0)
    }

    /// How well common curves match, as root-mean-square error in dB (volumes 5–90).
    private static func printFit(_ results: [(volume: Int, dB: Double)]) {
        let measured = results.filter { $0.volume >= 5 && $0.dB.isFinite }
        guard !measured.isEmpty else { return }
        let curves: [(name: String, curve: VolumeCurve)] = [
            ("linear (VolumeCurve.linear)", .linear),
            ("squared", VolumeCurve(exponent: 2)),
            ("cubic (VolumeCurve.cubic)", .cubic),
            ("x⁴", VolumeCurve(exponent: 4)),
        ]
        var models: [(name: String, dB: (Double) -> Double)] = curves.map { name, curve in
            (name, { curve.decibels(atVolume: $0) })
        }
        for range in [50.0, 60.0] {
            models.append(("dB-linear, \(Int(range)) dB range", { ($0 / 100 - 1) * range }))
        }
        func error(_ model: (Double) -> Double) -> Double {
            (measured.map { pow(model(Double($0.volume)) - $0.dB, 2) }.reduce(0, +) / Double(measured.count)).squareRoot()
        }
        print("\nFit (root-mean-square error in dB, volumes 5–90; lower is better):")
        for model in models.sorted(by: { error($0.dB) < error($1.dB) }) {
            print("  " + model.name.padding(toLength: 30, withPad: " ", startingAt: 0) + String(format: "%5.1f dB", error(model.dB)))
        }
    }

    /// Why a measurement can't be made, as shown to the user.
    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(1)
    }
}
