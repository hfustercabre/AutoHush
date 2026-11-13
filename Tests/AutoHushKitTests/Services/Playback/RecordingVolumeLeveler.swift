import Foundation
import AutoHushTestSupport
@testable import AutoHushKit

/// The real leveler over an output in memory, its lowerings recorded as
/// they take effect ("lower -6.0"): once per pause, a lowering asked for
/// again before the next pause left out, as on the Mac. Nothing puts it back.
final class RecordingVolumeLeveler: ResumeLeveling, @unchecked Sendable {
    private let volume = MockSystemVolume([0: -10], lowest: -200)
    private let leveler: SystemVolumeLeveler

    init() {
        leveler = SystemVolumeLeveler(volume: volume, defaults: MemoryDefaults())
    }

    /// Each lowering that took effect, by how much.
    var log: [String] {
        var before: Float = -10
        return volume.sets.map { set in
            let now = set[0] ?? before
            defer { before = now }
            return "lower \(now - before)"
        }
    }

    var lowerings: Int { leveler.lowerings }
    func lower(by decibels: Float) { leveler.lower(by: decibels) }
    func musicPaused(since lowerings: Int) { leveler.musicPaused(since: lowerings) }
}
