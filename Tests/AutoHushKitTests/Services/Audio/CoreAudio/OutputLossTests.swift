import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit

/// Pause on disconnect's reading of Core Audio's changes: the output in use
/// leaving the devices, before or after macOS announces the next one.
@Suite("OutputLoss")
struct OutputLossTests {
    private let headphones: AudioObjectID = 7, speakers: AudioObjectID = 3
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test("the output in use leaving the devices is a disconnect")
    func leaves() {
        var loss = OutputLoss()
        #expect(loss.update(output: headphones, current: headphones, devices: [speakers], now: start) != nil)
    }

    @Test("the next output announced first, then the old one leaving: a disconnect all the same, once")
    func leavesAfterTheSwitch() {
        var loss = OutputLoss()
        #expect(loss.update(output: headphones, current: speakers, devices: [headphones, speakers], now: start) == nil)
        #expect(loss.update(output: speakers, current: speakers, devices: [speakers], now: start + 0.5) != nil)
        #expect(loss.update(output: speakers, current: speakers, devices: [speakers], now: start + 1) == nil)
    }

    @Test("another output chosen by the user, the old one still there: no disconnect, nor when it leaves much later")
    func chosen() {
        var loss = OutputLoss()
        #expect(loss.update(output: headphones, current: speakers, devices: [headphones, speakers], now: start) == nil)
        #expect(loss.update(output: speakers, current: speakers, devices: [headphones, speakers], now: start + 1) == nil)
        #expect(loss.update(output: speakers, current: speakers, devices: [speakers],
                            now: start + CoreAudioOutputDisconnectWatcher.sameDisconnect + 1) == nil)
    }

    @Test("another device coming or going while the output in use stays: no disconnect")
    func otherDevices() {
        var loss = OutputLoss()
        #expect(loss.update(output: speakers, current: speakers, devices: [speakers, headphones], now: start) == nil)
        #expect(loss.update(output: speakers, current: speakers, devices: [speakers], now: start + 1) == nil)
    }
}
