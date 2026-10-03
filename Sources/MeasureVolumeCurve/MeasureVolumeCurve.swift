import AutoHushKit
import AutoHushPlayers
import CoreAudio
import Foundation

/// Measures how a music player turns its volume number (0–100) into loudness,
/// so its `VolumeCurve` can be set and fades sound even.
///
///     swift run measure-volume-curve [bundle-id] [volume …]
///
/// Works with any supported player (default: the one AutoHush controls). The
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
        let bundleID = arguments.first ?? SupportedPlayers.makeDefault().bundleID
        let requested = arguments.dropFirst().compactMap(Int.init)
        let volumes = requested.isEmpty ? defaultVolumes : requested

        guard let player = SupportedPlayers.player(bundleID: bundleID) else {
            fail("\(bundleID) is not a supported player (supported: \(SupportedPlayers.bundleIDs.sorted().joined(separator: ", ")))")
        }
        do {
            try await measure(player, volumes: volumes)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static func measure(_ player: any MusicPlayer, volumes: [Int]) async throws {
        try await player.verifyControlAccess()
        guard let originalVolume = await player.volume() else { fail("\(player.name) doesn't report its volume") }
        let wasPlaying = await player.playerState() == .playing
        print("\(player.name): volume \(originalVolume), \(wasPlaying ? "playing" : "not playing")")

        try await player.play()
        try await Task.sleep(for: .seconds(1))
        let processes = HALAudioProcessSnapshotProvider().activeProcesses()
            .filter { $0.bundleID == player.bundleID || $0.bundleID.hasPrefix(player.bundleID + ".") }
        guard !processes.isEmpty else { fail("no audio output from \(player.name); is it playing on this Mac?") }
        let meter = ProcessTapLevelMeter()
        meter.setMeteredProcesses(Set(processes.map(\.objectID)))
        defer { meter.stopAll() }
        try await Task.sleep(for: .milliseconds(500))

        func level(at volume: Int) async throws -> Double {
            try await player.setVolume(volume)
            try await Task.sleep(for: settle)
            _ = meter.drainLevels()
            try await Task.sleep(for: window)
            return Double(meter.drainLevels().values.map(\.rms).max() ?? 0)
        }

        func restore() async {
            try? await player.setVolume(originalVolume)
            if !wasPlaying { try? await player.pause() }
        }

        guard try await level(at: 100) > 0 else {
            await restore()
            fail("the tap hears silence: allow system audio recording for this tool (or the terminal running it) and try again")
        }

        var results: [(volume: Int, dB: Double)] = []
        for volume in volumes {
            var differences: [Double] = []
            for _ in 0..<pairsPerVolume {
                let full = try await level(at: 100)
                let reduced = try await level(at: volume)
                if full > 0 { differences.append(reduced > 0 ? 20 * log10(reduced / full) : -.infinity) }
            }
            let median = differences.sorted()[differences.count / 2]
            results.append((volume, median))
            print(median.isFinite ? String(format: "  volume %3d → %6.1f dB", volume, median) : String(format: "  volume %3d → silent", volume))
        }
        await restore()
        printFit(results)
    }

    /// How well common curves match, as root-mean-square error in dB (volumes 5–90).
    private static func printFit(_ results: [(volume: Int, dB: Double)]) {
        let measured = results.filter { $0.volume >= 5 && $0.dB.isFinite }
        guard !measured.isEmpty else { return }
        let models: [(name: String, curve: VolumeCurve?, dB: (Double) -> Double)] = [
            ("linear (VolumeCurve.linear)", .linear, { VolumeCurve.linear.decibels(atVolume: $0) }),
            ("squared", VolumeCurve(exponent: 2), { VolumeCurve(exponent: 2).decibels(atVolume: $0) }),
            ("cubic (VolumeCurve.cubic)", .cubic, { VolumeCurve.cubic.decibels(atVolume: $0) }),
            ("x⁴", VolumeCurve(exponent: 4), { VolumeCurve(exponent: 4).decibels(atVolume: $0) }),
            ("dB-linear, 50 dB range", nil, { ($0 / 100 - 1) * 50 }),
            ("dB-linear, 60 dB range", nil, { ($0 / 100 - 1) * 60 }),
        ]
        func error(_ model: (Double) -> Double) -> Double {
            (measured.map { pow(model(Double($0.volume)) - $0.dB, 2) }.reduce(0, +) / Double(measured.count)).squareRoot()
        }
        print("\nFit (root-mean-square error in dB, volumes 5–90; lower is better):")
        for model in models.sorted(by: { error($0.dB) < error($1.dB) }) {
            print("  " + model.name.padding(toLength: 30, withPad: " ", startingAt: 0) + String(format: "%5.1f dB", error(model.dB)))
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(1)
    }
}
