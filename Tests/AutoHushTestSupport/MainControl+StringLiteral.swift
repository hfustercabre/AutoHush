import AutoHushKit

/// A main control written as its kind's name in tests (`"menu"`), as it's
/// kept; the app's code makes one only from a kind (`WayOrder.Kind`).
extension MainControl: ExpressibleByStringLiteral {
    package init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}
