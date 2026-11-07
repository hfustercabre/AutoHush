import Accelerate
import CoreAudio
import Foundation
import os

/// A tap on some processes, read by a private aggregate device whose IO block
/// records their peak and average level. Unmuted, it only listens. Muted, the
/// processes can't be heard while it runs: macOS mutes a tap's processes
/// only while something reads it, so a tap alone mutes nothing (heard on
/// macOS 27).
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
    static func measure(_ bufferList: UnsafePointer<AudioBufferList>) -> (Float, Double, Int) {
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
