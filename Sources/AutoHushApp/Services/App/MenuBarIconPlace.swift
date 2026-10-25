import Foundation

/// Where AutoHush's icon goes in the menu bar as it's made. macOS puts a new
/// icon left of those already there, where the notch or a long menu hides it
/// first, and keeps where the user ⌘-drags it in the app's own defaults, under
/// a key it doesn't document (Ice and Hidden Bar use it too). A small value
/// written there before the icon is made puts it beside the system's icons,
/// ahead of other apps' (tested on macOS 27, 2026-10-22): once, unless the
/// user placed it already, and at each launch while the user keeps it there
/// (Settings → General). A macOS that ignores the key leaves the icon where
/// it would have gone anyway.
@MainActor
struct MenuBarIconPlace {
    /// The key macOS reads and writes for the app's first icon (its
    /// autosave name is "Item-0" unless it's given one).
    static let positionKey = "NSStatusItem Preferred Position Item-0"
    static let keepsKey = "keepsMenuBarIconNearSystemIcons"
    /// Set once the icon was placed beside the system's icons the first time.
    static let placedKey = "placedMenuBarIconNearSystemIcons"
    /// Beside the system's icons: the value tried on macOS 27 (the system's
    /// own icons keep theirs in Control Center's defaults).
    static let nearSystemIcons = 30.0

    let defaults: UserDefaults

    /// The switch's title, in Settings → General and Diagnostics.
    nonisolated static var title: String {
        String(localized: "Keep icon next to system icons",
               comment: "Settings → General and Diagnostics: whether AutoHush's menu bar icon goes back beside the system's icons (Control Center, the clock) each time AutoHush starts")
    }

    /// The icon goes back beside the system's icons at each launch.
    var keepsNearSystemIcons: Bool {
        get { defaults.bool(forKey: Self.keepsKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.keepsKey) }
    }

    /// Run before the icon is made: places it beside the system's icons the
    /// first time (unless the user moved it already) and at each launch
    /// while it's kept there.
    func prepare() {
        let firstTime = !defaults.bool(forKey: Self.placedKey) && defaults.object(forKey: Self.positionKey) == nil
        if firstTime || keepsNearSystemIcons {
            defaults.set(Self.nearSystemIcons, forKey: Self.positionKey)
        }
        defaults.set(true, forKey: Self.placedKey)
    }
}
