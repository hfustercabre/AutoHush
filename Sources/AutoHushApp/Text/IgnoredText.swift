import Foundation

/// Under an app that's ignored: the menu's Playing Now and Settings → Sound
/// Sources.
enum IgnoredText {
    static var label: String {
        String(localized: "Ignored — your player keeps playing", comment: "The menu's Playing Now and Settings → Sound Sources: under an app that is ignored, so your player keeps playing while it plays")
    }
}
