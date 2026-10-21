import AppKit
import SwiftUI

/// A style with one value in light mode and another in dark mode: only
/// Settings' sidebar keeps one of its own (`sidebarSelectionFill`).
struct AppearanceStyle: ShapeStyle {
    let light: AnyShapeStyle
    let dark: AnyShapeStyle

    init(light: some ShapeStyle, dark: some ShapeStyle) {
        self.light = AnyShapeStyle(light)
        self.dark = AnyShapeStyle(dark)
    }

    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        environment.colorScheme == .dark ? dark : light
    }
}

/// The colors the menu, Settings and the other windows share: macOS's own,
/// as it draws them in light and dark mode (the user, 2026-10-17: "use the
/// same that macOS is using"), named for what they're used for.
extension ShapeStyle where Self == HierarchicalShapeStyle {
    /// Descriptions under rows, section labels and captions.
    static var appSecondary: HierarchicalShapeStyle { .secondary }
}

extension ShapeStyle where Self == Color {
    /// Text and icons that need the user's attention.
    static var appWarning: Color { .orange }
    /// Text in the accent color the user picked, on its own tint (the
    /// "Recommended" `HeadingBadge`, a chosen card's included).
    static var appAccent: Color { .accentColor }
    /// Behind the control the arrow keys or the pointer highlight, or the
    /// keyboard's focus is on, in the menu and Settings (F5, the user's
    /// pick, 2026-10-18): the system's accent color, faint; it follows
    /// System Settings → Appearance.
    static var focusTint: Color { Color(nsColor: .controlAccentColor).opacity(0.14) }
    /// The same over the menu card's glass, which blends it away: a step
    /// stronger, so it shows as the rows' do (the user, 2026-10-18).
    static var cardFocusTint: Color { Color(nsColor: .controlAccentColor).opacity(0.24) }
    /// Icons for what works: Diagnostics' checks.
    static var appSuccess: Color { .green }
    /// A filled chip's background, at rest: the search field.
    static var chipFill: Color { Color(nsColor: .quaternarySystemFill) }
    /// A chip's background under the pointer: a step above `chipFill`.
    static var chipHoverFill: Color { Color(nsColor: .tertiarySystemFill) }
    /// Behind a `HeadingBadge`, a step's warning: `appWarning`, faint.
    static var warningBadgeFill: Color { .orange.opacity(0.15) }
    /// Behind what the user must do now: what the check's panel asks
    /// (`appAccent` on it), the accent color, faint.
    static var nextStepFill: Color { .accentColor.opacity(0.15) }
    /// Behind a list row the user selected (Settings → Sound Sources).
    static var selectedRowFill: Color { .accentColor.opacity(0.16) }
    /// Behind the chosen player's tile (`PlayerTiles`).
    static var selectedTileFill: Color { .accentColor.opacity(0.2) }
    /// The square behind a `SymbolTile`'s symbol (Settings' sidebar, the
    /// welcome window's permissions): the accent color the user picked, faint.
    static var symbolTileFill: Color { .accentColor.opacity(0.18) }
}

extension ShapeStyle where Self == AppearanceStyle {
    /// Behind the page shown, in Settings' sidebar.
    static var sidebarSelectionFill: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.1), dark: .quaternary)
    }
}
