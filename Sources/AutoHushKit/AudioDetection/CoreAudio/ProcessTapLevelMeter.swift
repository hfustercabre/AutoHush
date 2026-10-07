import Accelerate
import CoreAudio
import Foundation
import OSLog
import os

// MARK: - Level metering protocol

/// Measures how loud individual audio processes actually are, as opposed to
/// whether they merely hold an output stream open.
package protocol AudioLevelMetering: AnyObject, Sendable {
    /// Ensures exactly `objectIDs` are metered; taps for other processes are torn down.
    func setMeteredProcesses(_ objectIDs: Set<AudioObjectID>)
    /// Peak absolute sample value per metered process since the previous call.
    /// Processes whose tap could not be created are absent from the result.
    func drainPeaks() -> [AudioObjectID: Float]
    func stopAll()
}

/// How loud a process was over a stretch of time.
package struct AudioLevel: Equatable, Sendable {
    /// Largest absolute sample value (0…1).
    package var peak: Float
    /// Root-mean-square sample value (0…1): the average loudness.
    package var rms: Float
}

// MARK: - CoreAudio process tap implementation

/// Meters processes with CoreAudio process taps (macOS 14.2+).
///
/// Each metered process gets a private, unmuted tap wrapped in a private
/// aggregate device whose IO block records the peak and average (RMS) sample
/// level. Samples are inspected in memory only to compute those levels;
/// nothing is stored or sent.
///
/// Requires the "System Audio Recording" privacy permission. When it is denied
/// macOS still creates the tap but delivers silence, so callers must not treat
/// all-zero peaks as proof that a process is silent until a non-zero sample has
/// been seen at least once (see `AudioMonitor`).
///
/// Not thread-safe except for the IO blocks: call every method from one queue.
package final class ProcessTapLevelMeter: AudioLevelMetering, @unchecked Sendable {
    package init() {}

    private let logger = Logger(category: "LevelMeter")
    private let ioQueue = DispatchQueue(label: "AutoHush.LevelMeter.io", qos: .userInitiated)
    private var taps: [AudioObjectID: ProcessTap] = [:]
    /// Processes whose tap failed to start; not retried until they disappear.
    private var failed: Set<AudioObjectID> = []

    package func setMeteredProcesses(_ objectIDs: Set<AudioObjectID>) {
        for (objectID, tap) in taps where !objectIDs.contains(objectID) {
            tap.invalidate()
            taps[objectID] = nil
        }
        failed.formIntersection(objectIDs)

        for objectID in objectIDs where taps[objectID] == nil && !failed.contains(objectID) {
            do {
                taps[objectID] = try ProcessTap(processObjectIDs: [objectID], ioQueue: ioQueue)
                logger.debug("[meter] tapping process object \(objectID, privacy: .public)")
            } catch {
                failed.insert(objectID)
                logger.error("[meter] tap for process object \(objectID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    package func drainPeaks() -> [AudioObjectID: Float] {
        taps.mapValues { $0.drainLevel().peak }
    }

    /// Peak and average level per metered process since the previous call
    /// (used by the volume-curve tool; AutoHush itself only needs peaks).
    package func drainLevels() -> [AudioObjectID: AudioLevel] {
        taps.mapValues { $0.drainLevel() }
    }

    package func stopAll() {
        taps.values.forEach { $0.invalidate() }
        taps.removeAll()
        failed.removeAll()
    }

    deinit { stopAll() }
}

// MARK: - Single process tap

package struct ProcessTapError: LocalizedError {
    package let step: String
    package let status: OSStatus
    package var errorDescription: String? { "\(step) failed with OSStatus \(status)" }
}

/// A tap on some processes, read by a private aggregate device whose IO block
/// records their peak and average level. Unmuted, it only listens. Muted, the
/// processes can't be heard while it runs: macOS mutes a tap's processes only
/// while something reads it, so a tap alone mutes nothing (heard 2026-10-07).
///
/// Its owner creates, reads and invalidates it one call at a time; the levels
/// are locked.
final class ProcessTap: @unchecked Sendable {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private struct Accumulator {
        var peak: Float = 0
        var sumOfSquares: Double = 0
        var sampleCount = 0
    }

    private let accumulator = OSAllocatedUnfairLock(initialState: Accumulator())

    init(processObjectIDs: [AudioObjectID], muted: Bool = false, ioQueue: DispatchQueue) throws {
        do {
            try start(processObjectIDs: processObjectIDs, muted: muted, ioQueue: ioQueue)
        } catch {
            invalidate()
            throw error
        }
    }

    func drainLevel() -> AudioLevel {
        accumulator.withLock { value in
            defer { value = Accumulator() }
            let rms = value.sampleCount > 0 ? (value.sumOfSquares / Double(value.sampleCount)).squareRoot() : 0
            return AudioLevel(peak: value.peak, rms: Float(rms))
        }
    }

    func invalidate() {
        if aggregateID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func start(processObjectIDs: [AudioObjectID], muted: Bool, ioQueue: DispatchQueue) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.uuid = UUID()
        description.isPrivate = true
        // Muted only while read: should reading stop, the sound comes back.
        description.muteBehavior = muted ? .mutedWhenTapped : .unmuted
        try check("AudioHardwareCreateProcessTap", AudioHardwareCreateProcessTap(description, &tapID))
        try requireFloat32Format()

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: muted ? "AutoHush Mute" : "AutoHush Level Meter",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try check(
            "AudioHardwareCreateAggregateDevice",
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
        )

        let accumulator = self.accumulator
        try check("AudioDeviceCreateIOProcIDWithBlock", AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID, aggregateID, ioQueue
        ) { _, inputData, _, _, _ in
            let (peak, sumOfSquares, count) = ProcessTap.measure(inputData)
            accumulator.withLock {
                $0.peak = max($0.peak, peak)
                $0.sumOfSquares += sumOfSquares
                $0.sampleCount += count
            }
        })
        try check("AudioDeviceStart", AudioDeviceStart(aggregateID, ioProcID))
    }

    private func requireFloat32Format() throws {
        guard let format = CoreAudioProperty.value(
            kAudioTapPropertyFormat, of: tapID, initial: AudioStreamBasicDescription()
        ) else { throw ProcessTapError(step: "reading kAudioTapPropertyFormat", status: -1) }
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32
        else { throw ProcessTapError(step: "tap format is not Float32 PCM", status: -1) }
    }

    private func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else { throw ProcessTapError(step: step, status: status) }
    }

    /// Peak, sum of squares and sample count of one IO cycle's buffers.
    private static func measure(_ bufferList: UnsafePointer<AudioBufferList>) -> (Float, Double, Int) {
        var peak: Float = 0
        var sumOfSquares: Double = 0
        var total = 0
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList)) {
            guard let data = buffer.mData else { continue }
            let count = vDSP_Length(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
            guard count > 0 else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            var bufferPeak: Float = 0
            var bufferSquares: Float = 0
            vDSP_maxmgv(samples, 1, &bufferPeak, count)
            vDSP_svesq(samples, 1, &bufferSquares, count)
            peak = max(peak, bufferPeak)
            sumOfSquares += Double(bufferSquares)
            total += Int(count)
        }
        return (peak, sumOfSquares, total)
    }
}
