import Accelerate
import CoreAudio
import Foundation
import OSLog
import os

// MARK: - Level metering protocol

/// Measures how loud individual audio processes actually are, as opposed to
/// whether they merely hold an output stream open.
protocol AudioLevelMetering: AnyObject, Sendable {
    /// Ensures exactly `objectIDs` are metered; taps for other processes are torn down.
    func setMeteredProcesses(_ objectIDs: Set<AudioObjectID>)
    /// Peak absolute sample value per metered process since the previous call.
    /// Processes whose tap could not be created are absent from the result.
    func drainPeaks() -> [AudioObjectID: Float]
    func stopAll()
}

// MARK: - CoreAudio process tap implementation

/// Meters processes with CoreAudio process taps (macOS 14.2+).
///
/// Each metered process gets a private, unmuted tap wrapped in a private
/// aggregate device whose IO block records the peak sample value. Samples are
/// inspected in memory only to compute that peak; nothing is stored or sent.
///
/// Requires the "System Audio Recording" privacy permission. When it is denied
/// macOS still creates the tap but delivers silence, so callers must not treat
/// all-zero peaks as proof that a process is silent until a non-zero sample has
/// been seen at least once (see `AudioMonitor`).
///
/// Not thread-safe except for the IO blocks: call every method from one queue.
final class ProcessTapLevelMeter: AudioLevelMetering, @unchecked Sendable {
    private let logger = Logger(category: "LevelMeter")
    private let ioQueue = DispatchQueue(label: "AutoHush.LevelMeter.io", qos: .userInitiated)
    private var taps: [AudioObjectID: ProcessTap] = [:]
    /// Processes whose tap failed to start; not retried until they disappear.
    private var failed: Set<AudioObjectID> = []

    func setMeteredProcesses(_ objectIDs: Set<AudioObjectID>) {
        for (objectID, tap) in taps where !objectIDs.contains(objectID) {
            tap.invalidate()
            taps[objectID] = nil
        }
        failed.formIntersection(objectIDs)

        for objectID in objectIDs where taps[objectID] == nil && !failed.contains(objectID) {
            do {
                taps[objectID] = try ProcessTap(processObjectID: objectID, ioQueue: ioQueue)
                logger.debug("[meter] tapping process object \(objectID, privacy: .public)")
            } catch {
                failed.insert(objectID)
                logger.error("[meter] tap for process object \(objectID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func drainPeaks() -> [AudioObjectID: Float] {
        taps.mapValues { $0.drainPeak() }
    }

    func stopAll() {
        taps.values.forEach { $0.invalidate() }
        taps.removeAll()
        failed.removeAll()
    }

    deinit { stopAll() }
}

// MARK: - Single process tap

struct ProcessTapError: LocalizedError {
    let step: String
    let status: OSStatus
    var errorDescription: String? { "\(step) failed with OSStatus \(status)" }
}

private final class ProcessTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let peak = OSAllocatedUnfairLock<Float>(initialState: 0)

    init(processObjectID: AudioObjectID, ioQueue: DispatchQueue) throws {
        do {
            try start(processObjectID: processObjectID, ioQueue: ioQueue)
        } catch {
            invalidate()
            throw error
        }
    }

    func drainPeak() -> Float {
        peak.withLock { value in
            defer { value = 0 }
            return value
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

    private func start(processObjectID: AudioObjectID, ioQueue: DispatchQueue) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check("AudioHardwareCreateProcessTap", AudioHardwareCreateProcessTap(description, &tapID))
        try requireFloat32Format()

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AutoHush Level Meter",
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

        let peak = self.peak
        try check("AudioDeviceCreateIOProcIDWithBlock", AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID, aggregateID, ioQueue
        ) { _, inputData, _, _, _ in
            let level = ProcessTap.peakLevel(of: inputData)
            peak.withLock { $0 = max($0, level) }
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

    private static func peakLevel(of bufferList: UnsafePointer<AudioBufferList>) -> Float {
        var result: Float = 0
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList)) {
            guard let data = buffer.mData else { continue }
            let count = vDSP_Length(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
            guard count > 0 else { continue }
            var bufferPeak: Float = 0
            vDSP_maxmgv(data.assumingMemoryBound(to: Float.self), 1, &bufferPeak, count)
            result = max(result, bufferPeak)
        }
        return result
    }
}
