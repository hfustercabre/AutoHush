// Measures how a music player turns its "sound volume" (0–100) into loudness,
// so fades can follow the curve our ears hear (see VolumeFader).
//
// Usage: swift Scripts/measure-volume-curve.swift [bundle-id] [volume …]
//        (default: com.spotify.client at 90, 75, 60, 50, 40, 30, 20, 15, 10, 5, 2, 1)
//
// The player must be running; it plays your music for about 50 seconds at
// changing volumes, then gets its volume and play state back. Its output is
// read through a CoreAudio process tap to compute loudness only — nothing is
// recorded or stored. macOS asks once for permission to record system audio
// (revocable in System Settings → Privacy & Security → Screen & System Audio
// Recording) and to control the player.
//
// For each volume it alternates with 100 several times and reports the median
// level difference in dB, which cancels out the music's own ups and downs.
import AppKit
import CoreAudio
import Foundation

let bundleID = CommandLine.arguments.dropFirst().first ?? "com.spotify.client"
let requestedVolumes = CommandLine.arguments.dropFirst(2).compactMap { Int($0) }
let volumes = requestedVolumes.isEmpty ? [90, 75, 60, 50, 40, 30, 20, 15, 10, 5, 2, 1] : requestedVolumes
let pairsPerVolume = 4
let settle: TimeInterval = 0.2  // after a volume change, before measuring
let window: TimeInterval = 0.3  // measuring time per level

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("error: \(message)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - Controlling the player (AppleScript terms shared by Spotify and Music)

@discardableResult
func tell(_ command: String) -> NSAppleEventDescriptor {
    var error: NSDictionary?
    let script = NSAppleScript(source: "tell application id \"\(bundleID)\" to \(command)")!
    let result = script.executeAndReturnError(&error)
    if let error { fail("\(command): \(error[NSAppleScript.errorMessage] ?? error)") }
    return result
}

func setVolume(_ volume: Int) { tell("set sound volume to \(volume)") }

// MARK: - Listening to the player's output

func bundleIDProperty(of object: AudioObjectID) -> String? {
    var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
}

/// The player's CoreAudio process objects (its app and helpers).
func playerProcesses() -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
    return ids.filter { id in
        guard let name = bundleIDProperty(of: id) else { return false }
        return name == bundleID || name.hasPrefix(bundleID + ".")
    }
}

/// Sum of squared samples and their count since the last reset.
final class Meter: @unchecked Sendable {
    private let lock = NSLock()
    private var sum: Double = 0
    private var count = 0

    func add(_ buffers: UnsafePointer<AudioBufferList>) {
        var localSum: Double = 0
        var localCount = 0
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffers)) {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let n = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            for i in 0..<n { localSum += Double(samples[i] * samples[i]) }
            localCount += n
        }
        lock.lock(); sum += localSum; count += localCount; lock.unlock()
    }

    /// Root-mean-square level since the last call.
    func takeRMS() -> Double {
        lock.lock(); defer { sum = 0; count = 0; lock.unlock() }
        return count > 0 ? (sum / Double(count)).squareRoot() : 0
    }
}

let meter = Meter()

func startTap(on processes: [AudioObjectID]) {
    let description = CATapDescription(stereoMixdownOfProcesses: processes)
    description.uuid = UUID()
    description.isPrivate = true
    description.muteBehavior = .unmuted
    var tapID = AudioObjectID(kAudioObjectUnknown)
    guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { fail("could not create the process tap") }

    let aggregate: [String: Any] = [
        kAudioAggregateDeviceNameKey: "Volume curve meter",
        kAudioAggregateDeviceUIDKey: UUID().uuidString,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
    ]
    var deviceID = AudioObjectID(kAudioObjectUnknown)
    guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID) == noErr else { fail("could not create the meter device") }
    var procID: AudioDeviceIOProcID?
    let queue = DispatchQueue(label: "meter")
    AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue) { _, input, _, _, _ in meter.add(input) }
    guard AudioDeviceStart(deviceID, procID) == noErr else { fail("could not start the meter") }
}

// MARK: - Measuring

func level(at volume: Int) -> Double {
    setVolume(volume)
    Thread.sleep(forTimeInterval: settle)
    _ = meter.takeRMS()
    Thread.sleep(forTimeInterval: window)
    return meter.takeRMS()
}

func dB(_ ratio: Double) -> Double { ratio > 0 ? 20 * log10(ratio) : -.infinity }

guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { !$0.isTerminated }) else {
    fail("\(bundleID) is not running")
}
let originalVolume = Int(tell("get sound volume").int32Value)
let wasPlaying = tell("get player state as string").stringValue == "playing"
print("\(bundleID): volume \(originalVolume), \(wasPlaying ? "playing" : "not playing")")

tell("play")
Thread.sleep(forTimeInterval: 1)
let processes = playerProcesses()
guard !processes.isEmpty else { fail("no audio process found for \(bundleID)") }
startTap(on: processes)
Thread.sleep(forTimeInterval: 0.5)

if level(at: 100) == 0 {
    tell("pause"); setVolume(originalVolume)
    fail("the tap hears silence: allow system audio recording for this tool (or the terminal running it) and try again")
}

var results: [(volume: Int, dB: Double)] = []
for volume in volumes {
    var differences: [Double] = []
    for _ in 0..<pairsPerVolume {
        let full = level(at: 100)
        let reduced = level(at: volume)
        if full > 0 { differences.append(dB(reduced / full)) }
    }
    let median = differences.sorted()[differences.count / 2]
    results.append((volume, median))
    print(median.isFinite ? String(format: "  volume %3d → %6.1f dB", volume, median) : String(format: "  volume %3d → silent", volume))
}

setVolume(originalVolume)
if !wasPlaying { tell("pause") }

// MARK: - Which curve fits?

let models: [(name: String, dB: (Double) -> Double)] = [
    ("linear (gain = v)", { 20 * log10($0) }),
    ("squared (gain = v²)", { 40 * log10($0) }),
    ("cubic (gain = v³)", { 60 * log10($0) }),
    ("x⁴ (gain = v⁴)", { 80 * log10($0) }),
    ("dB-linear, 40 dB range", { ($0 - 1) * 40 }),
    ("dB-linear, 50 dB range", { ($0 - 1) * 50 }),
    ("dB-linear, 60 dB range", { ($0 - 1) * 60 }),
]
print("\nFit (root-mean-square error in dB, volumes 5–90; lower is better):")
let fitted = results.filter { $0.volume >= 5 && $0.dB.isFinite }
for model in models.sorted(by: { lhs, rhs in
    func error(_ m: (Double) -> Double) -> Double {
        (fitted.map { pow(m(Double($0.volume) / 100) - $0.dB, 2) }.reduce(0, +) / Double(fitted.count)).squareRoot()
    }
    return error(lhs.dB) < error(rhs.dB)
}) {
    let error = (fitted.map { pow(model.dB(Double($0.volume) / 100) - $0.dB, 2) }.reduce(0, +) / Double(fitted.count)).squareRoot()
    print("  " + model.name.padding(toLength: 26, withPad: " ", startingAt: 0) + String(format: "%5.1f dB", error))
}
