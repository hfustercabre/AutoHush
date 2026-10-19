import Foundation
import Testing
@testable import AutoHushApp

@Suite("Array helpers")
struct ArrayHelpersTests {
    @Test("← and → step through a choice and stop at its ends; nothing when the choice isn't in it")
    func stepping() {
        let ways = ["signals", "streams"]
        #expect(ways.stepping(from: "signals", by: 1) == "streams")
        #expect(ways.stepping(from: "streams", by: 1) == "streams") // the end
        #expect(ways.stepping(from: "streams", by: -1) == "signals")
        #expect(ways.stepping(from: "signals", by: -1) == "signals") // the start
        #expect(ways.stepping(from: "levels", by: 1) == nil)
        #expect([String]().stepping(from: "signals", by: 1) == nil)
    }

    @Test("rows keep their identity as others come and go; rows sharing a key are told apart by their order")
    func keyed() {
        let first = ["a", "b", "a", "c"].keyed(by: \.self)
        #expect(first.map(\.offset) == [0, 1, 2, 3])
        #expect(Set(first.map(\.id)).count == 4)
        #expect(first.map(\.id.occurrence) == [0, 0, 1, 0])
        // The first goes, a new one comes: "b" and "c" keep theirs.
        let later = ["b", "a", "c", "d"].keyed(by: \.self)
        #expect(later[0].id == first[1].id && later[2].id == first[3].id)
        #expect(later.map(\.element) == ["b", "a", "c", "d"])
    }
}
