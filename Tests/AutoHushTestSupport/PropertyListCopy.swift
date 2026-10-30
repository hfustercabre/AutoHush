import Foundation
import Testing

/// `value` as UserDefaults keeps it: written as a property list and read
/// back, in the Foundation form UserDefaults hands back. One that isn't a
/// property list (a Set, a struct, which UserDefaults can't store) is an
/// issue, and kept as it is.
package func propertyListCopy(_ value: Any, forKey key: String) -> Any {
    do {
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        return try PropertyListSerialization.propertyList(from: data, format: nil)
    } catch {
        Issue.record("\(key) isn't a property list, which UserDefaults can't store: \(value)")
        return value
    }
}
