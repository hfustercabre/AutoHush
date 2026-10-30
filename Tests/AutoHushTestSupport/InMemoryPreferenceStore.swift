import Foundation
import AutoHushKit

/// Keeps preferences in memory, so tests never write preference files. Each
/// value is kept as UserDefaults keeps it, as a property list: one that
/// isn't (a Set, a struct, which UserDefaults can't store) is an issue, and
/// what's read back is the Foundation form UserDefaults hands back.
package final class InMemoryPreferenceStore: PreferenceStore {
    package init() {}
    private var values: [String: Any] = [:]

    package func object(forKey key: String) -> Any? { values[key] }

    package func set(_ value: Any?, forKey key: String) {
        values[key] = value.map { propertyListCopy($0, forKey: key) }
    }
}
