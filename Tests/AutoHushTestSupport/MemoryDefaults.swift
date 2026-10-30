import Foundation

/// UserDefaults kept in memory, for code that takes a `UserDefaults`: no
/// file and no preferences daemon, so what's saved or removed is read back
/// at once. A suite named by a path (`TestDefaults`, retired 2026-10-27)
/// once handed CI an older value, read within the same second it was
/// changed. Every typed getter and setter of UserDefaults goes through
/// `object(forKey:)`, `set(_:forKey:)` and `removeObject(forKey:)` (measured
/// 2026-10-26);
/// anything else reaches a suite in a folder that doesn't exist, which
/// keeps nothing. Each value is kept as UserDefaults keeps it, as a property
/// list, like `InMemoryPreferenceStore`.
package final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    package init() {
        super.init(suiteName: FileManager.default.temporaryDirectory.appending(path: "MemoryDefaults-\(UUID().uuidString)/none").path)!
    }

    override package func object(forKey key: String) -> Any? {
        lock.withLock { values[key] }
    }

    override package func set(_ value: Any?, forKey key: String) {
        guard let value else { return removeObject(forKey: key) }
        let kept = propertyListCopy(value, forKey: key)
        lock.withLock { values[key] = kept }
    }

    override package func removeObject(forKey key: String) {
        lock.withLock { values[key] = nil }
    }
}
