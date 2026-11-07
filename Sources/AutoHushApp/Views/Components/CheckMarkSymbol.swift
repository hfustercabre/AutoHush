import AppKit
import SwiftUI
import CheckedPlayers

/// A check's mark as AutoHush draws it: its symbol, in the color token for
/// what it says. One table for Add an App's ways and the controls' Details
/// sheet (`WayRow.symbol`) and Fine-Tuning's Main control pop-up
/// (`PlayerControlsCard.markImage`), every mark listed, so a new one is
/// given its look here, for both.
struct CheckMarkSymbol {
    /// What the mark's color says: `appSuccess`, `appWarning` or `appSecondary`.
    enum Tone { case success, warning, secondary }

    let name: String
    let tone: Tone

    init(_ mark: CheckResult.Mark) {
        let (name, tone): (String, Tone) = switch mark {
        case .works: ("checkmark.circle.fill", .success)
        case .some: ("exclamationmark.circle.fill", .warning)
        case .none, .notThere: ("xmark.circle.fill", .secondary)
        case .notTried, .notChecked, .noWindow, .noAutomation, .noAccessibility, .menuBarHidden, .toggleOnly:
            ("minus.circle", .secondary)
        }
        self.name = name
        self.tone = tone
    }

    /// Its color token.
    var style: AnyShapeStyle {
        switch tone {
        case .success: AnyShapeStyle(.appSuccess)
        case .warning: AnyShapeStyle(.appWarning)
        case .secondary: AnyShapeStyle(.appSecondary)
        }
    }

    /// The same token for AppKit (a menu item's image): `appSecondary`, a
    /// hierarchical style, as macOS's secondary label color, which it is.
    var nsColor: NSColor {
        switch tone {
        case .success: NSColor(Color.appSuccess)
        case .warning: NSColor(Color.appWarning)
        case .secondary: .secondaryLabelColor
        }
    }
}
