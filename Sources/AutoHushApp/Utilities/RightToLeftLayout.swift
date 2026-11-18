import Foundation
import SwiftUI

/// AutoHush in Arabic or Hebrew lays itself out right to left, as macOS's
/// own apps do. macOS mirrors only a window's title bar by itself: an app
/// whose layouts come from Interface Builder files gets them flipped as they
/// load, but AutoHush makes its views in code, and AppKit's direction (with
/// SwiftUI's that follows it) stays left to right unless `AppleTextDirection`
/// says otherwise (measured in the VM with macOS in Arabic, 2026-11-18). So
/// it's registered, as a default only: someone who sets it themselves keeps
/// their setting.
enum RightToLeftLayout {
    static let key = "AppleTextDirection"

    /// Whether `language` (a localization, as `ar` or `he`) reads right to left.
    static func readsRightToLeft(_ language: String?) -> Bool {
        guard let language else { return false }
        return Locale.Language(identifier: language).characterDirection == .rightToLeft
    }

    /// What's registered: AppKit's direction right to left when `preferred`
    /// (the localizations AutoHush runs in, best first) starts with Arabic
    /// or Hebrew; nothing otherwise.
    static func defaults(preferred: [String]) -> [String: Any] {
        readsRightToLeft(preferred.first) ? [key: true] : [:]
    }

    /// Before the app starts, when AppKit reads it. Registered defaults are
    /// the whole process's, below anything set.
    static func register(preferred: [String] = Bundle.main.preferredLocalizations) {
        let values = defaults(preferred: preferred)
        if !values.isEmpty { UserDefaults.standard.register(defaults: values) }
    }

    /// The step for an arrow (→ 1, ← -1) on a control laid out along a line,
    /// a slider or a row of chips, so it moves the way the arrow points, as
    /// macOS's own do: right to left, where a slider's minimum and a row's
    /// first chip are on the right, → steps back (measured on `NSSlider` and
    /// `NSSegmentedControl`, 2026-11-18; the user: "Follow how MacOS manages it").
    static func arrowStep(_ arrow: Int, in layoutDirection: LayoutDirection) -> Int {
        layoutDirection == .rightToLeft ? -arrow : arrow
    }
}
