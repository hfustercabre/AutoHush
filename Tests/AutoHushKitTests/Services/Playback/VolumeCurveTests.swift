import Foundation
import Testing
@testable import AutoHushKit

@Suite("VolumeCurve")
struct VolumeCurveTests {
    @Test("a cube law puts half volume at about −18 dB, and converts back")
    func cubic() {
        #expect(abs(VolumeCurve.cubic.decibels(atVolume: 50) - -18.06) < 0.01)
        #expect(abs(VolumeCurve.cubic.volume(atDecibels: -18.06) - 50) < 0.1)
        #expect(VolumeCurve.cubic.decibels(atVolume: 100) == 0)
        #expect(VolumeCurve.cubic.decibels(atVolume: 0) == -.infinity)
    }

    @Test("a linear curve puts half volume at about −6 dB")
    func linear() {
        #expect(abs(VolumeCurve.linear.decibels(atVolume: 50) - -6.02) < 0.01)
    }
}
