import AppIntents

// AutoHush's two ready-made App Shortcuts: they show in Shortcuts, Spotlight
// and Siri without the user building anything. Siri needs each phrase to name
// the app, so both hold `\(.applicationName)`. The phrases are in
// Resources/Localization/AppShortcuts.xcstrings (keys with `${applicationName}`),
// which the build compiles with the other catalogs. Everything here is a
// literal: the build's metadata step reads it from the source.

struct AutoHushShortcuts: AppShortcutsProvider {
    /// Purple, like the app's icon.
    static let shortcutTileColor: ShortcutTileColor = .purple

    /// Off first, then On.
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetAutoPauseIntent(operation: .turnOff),
            phrases: ["Turn off Auto-Pause in \(.applicationName)"],
            shortTitle: LocalizedStringResource(
                "Auto-Pause Off",
                comment: "Shortcuts and Focus: Auto-Pause turned off (a Focus filter's setting, an App Shortcut's title)"),
            systemImageName: "waveform.slash")
        AppShortcut(
            intent: SetAutoPauseIntent(operation: .turnOn),
            phrases: ["Turn on Auto-Pause in \(.applicationName)"],
            shortTitle: LocalizedStringResource(
                "Auto-Pause On",
                comment: "Shortcuts and Focus: Auto-Pause turned on (a Focus filter's setting, an App Shortcut's title)"),
            systemImageName: "waveform")
    }
}
