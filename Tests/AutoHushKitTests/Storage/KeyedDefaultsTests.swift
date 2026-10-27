import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("KeyedDefaults")
struct KeyedDefaultsTests {
    @Test("values are set and removed by ID; changes from many queues at once are all kept; a change that changes nothing writes nothing")
    func keeps() async {
        let defaults = MemoryDefaults()
        let stored = KeyedDefaults(key: "things", defaults: defaults)
        stored.set("a", for: "one")
        stored.set(nil, for: "none")
        #expect(stored.values() as? [String: String] == ["one": "a"])
        stored.set(nil, for: "one")
        #expect(stored.values().isEmpty)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 { group.addTask { stored.set(index, for: "\(index)") } }
        }
        #expect(stored.values().count == 50) // none lost to another's write

        defaults.removeObject(forKey: "things")
        stored.change { _ in false }
        #expect(defaults.object(forKey: "things") == nil)
    }
}
