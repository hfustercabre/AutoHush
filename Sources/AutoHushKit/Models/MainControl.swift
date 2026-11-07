/// A control chosen as a player's main one in Settings
/// (`BackupSwitches.mainControl`), by its kind's name ("script", "menu",
/// "page", "panel"), as the players' modules name their ways
/// (`WayOrder.Kind`, which maps to and from it): kept as that text.
package struct MainControl: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    package let rawValue: String

    package init(rawValue: String) {
        self.rawValue = rawValue
    }

    package var description: String { rawValue }
}
