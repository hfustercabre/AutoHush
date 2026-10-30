import AutoHushKit
import CoreAudio
import Foundation
import os

/// Listens to AutoHush's fades the way you hear them: it records a loopback
/// audio device (an output whose sound comes back on its input) while the
/// music fades, then measures the music's loudness through each fade.
///
///     swift run listen-to-fades record <seconds> <file.wav> [--device <UID>]
///     swift run listen-to-fades analyze <file.wav> [--fade-out 1] [--fade-in 2] [--log <file>]
///
/// Set the Mac's sound output to the loopback device first; you hear nothing
/// meanwhile. Recording a device's input needs the Microphone permission for
/// the app that runs the tool (macOS asks once). Only that device is read.
///
/// `analyze` takes the fades' times from AutoHush's own log, removes the
/// test beep (523 Hz) and, for every fade, prints the music's level every
/// 50 ms next to an ideal straight-line fade, and any dropouts or jumps.
/// AutoHush gives macOS's log its lines at the debug level only, which
/// macOS keeps only for a live `log stream`: capture one during the test and
/// pass it with `--log` (compact style), else `log show` is asked, which
/// finds none.
@main
enum ListenToFades {
    static let defaultDevice = "AutoHushLoopback_UID"
    static let beep = 523.25

    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        func option(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
            defer { arguments.removeSubrange(index...(index + 1)) }
            return arguments[index + 1]
        }
        let device = option("--device") ?? defaultDevice
        let fadeOut = option("--fade-out").flatMap(Double.init) ?? 1
        let fadeIn = option("--fade-in").flatMap(Double.init) ?? 2
        let log = option("--log")
        switch arguments.first {
        case "record" where arguments.count == 3:
            guard let seconds = Double(arguments[1]) else { usage() }
            record(device: device, seconds: seconds, to: arguments[2])
        case "analyze" where arguments.count == 2:
            analyze(arguments[1], fadeOut: fadeOut, fadeIn: fadeIn, log: log)
        default:
            usage()
        }
    }

    static func usage() -> Never {
        print("""
        usage: listen-to-fades record <seconds> <file.wav> [--device <UID>]
               listen-to-fades analyze <file.wav> [--fade-out 1] [--fade-in 2] [--log <file>]
        """)
        exit(2)
    }

    /// The times of the log's lines and of the recording's start, read and
    /// written alike whatever the Mac's language and calendar (QA1480).
    static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    // MARK: - Recording

    /// Records the device's input to a 32-bit float WAV, and the time of its
    /// first sample next to it (`<file>.start`).
    static func record(device uid: String, seconds: Double, to path: String) {
        guard let device = CoreAudioProperty.device(withUID: uid) else {
            print("No audio device with UID \(uid).")
            exit(1)
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamFormat, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &format) == noErr,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
            print("The device's input isn't 32-bit float.")
            exit(1)
        }
        let channels = Int(format.mChannelsPerFrame)
        let wanted = Int(format.mSampleRate * seconds) * channels
        let state = OSAllocatedUnfairLock(initialState: (samples: [Float](), first: Date?.none))
        state.withLock { $0.samples.reserveCapacity(wanted) }
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, device, DispatchQueue(label: "record")) { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            var chunk: [Float] = []
            if buffers.count == 1, let data = buffers[0].mData {
                let count = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
                chunk = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
            } else { // one buffer per channel: interleave them
                let frames = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
                for frame in 0..<frames {
                    for buffer in buffers { chunk.append(buffer.mData.map { $0.assumingMemoryBound(to: Float.self)[frame] } ?? 0) }
                }
            }
            let now = Date()
            let cycle = chunk
            state.withLock { state in
                if state.first == nil { state.first = now }
                guard state.samples.count < wanted else { return }
                state.samples.append(contentsOf: cycle)
            }
        }
        guard status == noErr, AudioDeviceStart(device, procID) == noErr else {
            print("Couldn't start recording (OSStatus \(status)).")
            exit(1)
        }
        print("Recording \(seconds) s from \(uid) (\(format.mSampleRate) Hz, \(channels) ch)…")
        Thread.sleep(forTimeInterval: seconds + 0.3)
        AudioDeviceStop(device, procID)
        AudioDeviceDestroyIOProcID(device, procID!)
        let (samples, first) = state.withLock { ($0.samples, $0.first) }
        guard let first, samples.contains(where: { $0 != 0 }) else {
            print("Only silence was recorded: is the sound output set to the device, and is the Microphone permission given?")
            exit(1)
        }
        writeWAV(samples, channels: channels, rate: format.mSampleRate, to: path)
        try? stamp.string(from: first).write(toFile: path + ".start", atomically: true, encoding: .utf8)
        print("Saved \(path): \(samples.count / channels) frames from \(stamp.string(from: first)).")
    }

    static func writeWAV(_ samples: [Float], channels: Int, rate: Double, to path: String) {
        var data = Data()
        func put<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        let bytes = samples.count * MemoryLayout<Float>.size
        data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16)); put(UInt16(3)) // IEEE float
        put(UInt16(channels)); put(UInt32(rate)); put(UInt32(Int(rate) * channels * 4)); put(UInt16(channels * 4)); put(UInt16(32))
        data.append(contentsOf: Array("data".utf8)); put(UInt32(bytes))
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        do { try data.write(to: URL(fileURLWithPath: path)) } catch {
            print("Couldn't save \(path): \(error.localizedDescription)")
            exit(1)
        }
    }

    // MARK: - Analysis

    struct Event {
        enum Kind: String {
            case fadeOut = "fade out", fadeIn = "fade in"
        }
        let time: Date
        let kind: Kind
    }

    static func analyze(_ path: String, fadeOut: Double, fadeIn: Double, log: String?) {
        guard let wav = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let startText = try? String(contentsOfFile: path + ".start", encoding: .utf8),
              let start = stamp.date(from: startText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            print("Can't read \(path) and \(path).start.")
            exit(1)
        }
        let channels = Int(wav.subdata(in: 22..<24).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) })
        let rate = Double(wav.subdata(in: 24..<28).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        let samples: [Float] = wav.subdata(in: 44..<wav.count).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let frames = samples.count / channels
        var mono = [Double](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum = 0.0
            for channel in 0..<channels { sum += Double(samples[frame * channels + channel]) }
            mono[frame] = sum / Double(channels)
        }
        let music = notch(notch(mono, frequency: beep, rate: rate), frequency: beep, rate: rate)
        let meter = Meter(music: music, rate: rate)
        let end = start.addingTimeInterval(Double(frames) / rate)
        let events = (log.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? logShow(from: start, to: end))
            .split(separator: "\n").compactMap(event).filter { $0.time >= start && $0.time <= end }
        print(String(format: "%@: %.1f s at %.0f Hz from %@; %d fades in AutoHush's log", path, Double(frames) / rate, rate, stamp.string(from: start), events.count))

        for fade in events {
            let out = fade.kind == .fadeOut
            let duration = out ? fadeOut : fadeIn
            let t0 = fade.time.timeIntervalSince(start)
            // Full volume: the music just before a fade-out, or once a fade-in is over.
            let full = out ? meter.level(from: t0 - 0.6, to: t0 - 0.05) : meter.level(from: t0 + duration + 0.5, to: t0 + duration + 1.5)
            print("\n=== \(fade.kind.rawValue) at \(stamp.string(from: fade.time)) (\(duration) s); full-volume music \(String(format: "%.1f", full)) dB")
            print("    t (s)   heard   ideal   (dB below full volume, 50 ms each)")
            var t = -0.3
            while t < duration + 0.6 {
                let heard = meter.level(from: t0 + t, to: t0 + t + 0.05) - full
                let share = out ? 1 - t / duration : t / duration
                let ideal = t < 0 ? (out ? 0 : -99) : t > duration ? (out ? -99 : 0) : 20 * log10(max(share, 0.00001))
                let bar = String(repeating: "█", count: max(0, Int((heard + 60) / 2)))
                print(String(format: "  %6.2f  %6.1f  %6.1f   %@", t, heard, max(ideal, -99), bar))
                t += 0.05
            }
            let flags = meter.flags(from: t0 - 0.3, to: t0 + duration + 0.6, origin: t0)
            print("  dropouts and jumps: " + (flags.isEmpty ? "none" : flags.prefix(16).joined(separator: "; ")))
        }
    }

    /// The music's level, 5 ms at a time.
    struct Meter {
        let levels: [Double] // dB, one per 5 ms (10 ms windows)
        static let hop = 0.005

        init(music: [Double], rate: Double) {
            let hop = Int(rate * Self.hop), window = 2 * hop
            var levels: [Double] = []
            var index = 0
            while index + window < music.count {
                var sum = 0.0
                for i in index..<(index + window) { sum += music[i] * music[i] }
                levels.append(10 * log10(sum / Double(window) + 1e-12))
                index += hop
            }
            self.levels = levels
        }

        func index(_ seconds: Double) -> Int { Int((seconds / Self.hop).rounded()) }

        /// The average level between two times since the recording started.
        func level(from: Double, to: Double) -> Double {
            let range = max(0, index(from))..<min(levels.count, max(index(from) + 1, index(to)))
            guard !range.isEmpty else { return -120 }
            let power = range.map { pow(10, levels[$0] / 10) }.reduce(0, +) / Double(range.count)
            return 10 * log10(power + 1e-12)
        }

        /// Sudden dips (a dropout) and rises (a jump), with their time from `origin`.
        func flags(from: Double, to: Double, origin: Double) -> [String] {
            var flags: [String] = []
            for k in max(2, index(from))..<min(levels.count - 2, index(to)) {
                let around = (levels[k - 2] + levels[k + 2]) / 2
                let at = Double(k) * Self.hop - origin
                if levels[k] < around - 12 { flags.append(String(format: "dip %.0f dB at %+.3f s", levels[k] - around, at)) }
                if levels[k] - levels[k - 1] > 8 { flags.append(String(format: "rise +%.0f dB at %+.3f s", levels[k] - levels[k - 1], at)) }
            }
            return flags
        }
    }

    /// A notch filter: removes the beep and little else.
    static func notch(_ x: [Double], frequency: Double, rate: Double, q: Double = 8) -> [Double] {
        let w0 = 2 * Double.pi * frequency / rate, alpha = sin(w0) / (2 * q), c = cos(w0), a0 = 1 + alpha
        let b0 = 1 / a0, b1 = -2 * c / a0, b2 = 1 / a0, a1 = -2 * c / a0, a2 = (1 - alpha) / a0
        var y = [Double](repeating: 0, count: x.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<x.count {
            let v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x[i]; y2 = y1; y1 = v; y[i] = v
        }
        return y
    }

    /// AutoHush's log over the recording, from `log show`.
    static func logShow(from start: Date, to end: Date) -> String {
        let short = DateFormatter()
        short.locale = Locale(identifier: "en_US_POSIX")
        short.calendar = Calendar(identifier: .gregorian)
        short.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return ToolRun(URL(fileURLWithPath: "/usr/bin/log"), [
            "show", "--style", "compact", "--info", "--debug",
            "--start", short.string(from: start.addingTimeInterval(-1)), "--end", short.string(from: end.addingTimeInterval(1)),
            "--predicate", "subsystem == \"\(AutoHushLogger.subsystem)\"",
        ]).runBlocking().text
    }

    /// A fade, from one line of AutoHush's log (compact style).
    static func event(_ line: Substring) -> Event? {
        guard line.count > 23, let time = stamp.date(from: String(line.prefix(23))) else { return nil }
        let kind: Event.Kind
        if line.contains("[fade] out from") { kind = .fadeOut }
        else if line.contains("[fade] in to") { kind = .fadeIn }
        else { return nil }
        return Event(time: time, kind: kind)
    }
}
