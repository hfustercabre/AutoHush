import Foundation
@testable import AutoHushKit
import AutoHushTestSupport

/// Counts the volume leveler's put-backs at once, whatever was lowered or
/// not (it lowers nothing).
final class CountingLeveler: ResumeLeveling {
    private let count = Locked(0)
    var restores: Int { count.value }

    func lower(by decibels: Float) -> UUID? { nil }
    func restore(over duration: TimeInterval, lowered token: UUID) {}
    func restoreNow(lowered token: UUID) { count.increment() }
    func restoreNow() { count.increment() }
}
