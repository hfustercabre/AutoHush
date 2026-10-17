import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit

@Suite("ProcessTapLevelMeter")
struct ProcessTapLevelMeterTests {
    @Test("each IO cycle's peak, sum of squares and sample count cover all its buffers, skipping empty ones")
    func measure() {
        let left: [Float] = [0.5, -0.8]
        let right: [Float] = [0.1, 0.3, -0.2]
        let list = AudioBufferList.allocate(maximumBuffers: 4)
        defer { free(list.unsafeMutablePointer) }
        left.withUnsafeBufferPointer { left in
            right.withUnsafeBufferPointer { right in
                list[0] = Self.buffer(left)
                list[1] = Self.buffer(right)
                list[2] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: UnsafeMutableRawPointer(mutating: left.baseAddress))
                list[3] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 8, mData: nil)
                let (peak, sumOfSquares, count) = ProcessTap.measure(list.unsafePointer)
                #expect(peak == 0.8) // the loudest sample, either way up
                #expect(abs(sumOfSquares - 1.03) < 1e-6)
                #expect(count == 5)
            }
        }
    }

    private static func buffer(_ samples: UnsafeBufferPointer<Float>) -> AudioBuffer {
        AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(samples.count * MemoryLayout<Float>.size),
                    mData: UnsafeMutableRawPointer(mutating: samples.baseAddress))
    }
}
