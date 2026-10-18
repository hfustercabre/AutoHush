import SwiftUI
import Testing
@testable import AutoHushApp

/// The choices' own size: never wider than they're offered.
@Suite("ChoiceChips")
@MainActor
struct ChoiceChipsTests {
    @Test("as wide as offered, never wider, even when they'd fit wider; their fitting width when offered none; their fitting height")
    func size() {
        let fitting = CGSize(width: 320, height: 22)
        #expect(ChoiceChips<Int>.size(ProposedViewSize(width: 300, height: 50), fitting: fitting) == CGSize(width: 300, height: 22))
        #expect(ChoiceChips<Int>.size(ProposedViewSize(width: 400, height: nil), fitting: fitting) == CGSize(width: 400, height: 22))
        #expect(ChoiceChips<Int>.size(.unspecified, fitting: fitting) == fitting)
    }
}
