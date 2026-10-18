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
    /// The menu's own background, near enough: what its last rows fade
    /// into while more is below (`MenuPanelView`).
    static var menuBackground: Color { Color(nsColor: .windowBackgroundColor) }
    /// Icons for what works: Diagnostics' checks.
    static var appSuccess: Color { .green }
    /// A filled chip's background, at rest: the search field, the menu's chevron.
    static var chipFill: Color { Color(nsColor: .quaternarySystemFill) }
    /// A chip's background under the pointer: a step above `chipFill`.
    static var chipHoverFill: Color { Color(nsColor: .tertiarySystemFill) }
    /// Behind a `HeadingBadge`, a step's warning: `appWarning`, faint.
    static var warningBadgeFill: Color { .orange.opacity(0.15) }
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
