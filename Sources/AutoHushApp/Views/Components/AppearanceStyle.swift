import SwiftUI

/// A style with one value in light mode and another in dark mode. The
/// system's secondary text, orange and fills are too faint in light mode,
/// on the menu's white and on Settings' grey, so light mode gets darker ones;
/// dark mode keeps the system's.
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

/// The colors the menu, Settings and the welcome window share. In light
/// mode, text keeps a contrast of at least 4.5:1 against its background.
extension ShapeStyle where Self == AppearanceStyle {
    /// Descriptions under rows, section labels and captions.
    static var appSecondary: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.68), dark: .secondary)
    }
    /// Text and icons that need the user's attention: a deep orange in light
    /// mode, where the system's is hard to read.
    static var appWarning: AppearanceStyle {
        AppearanceStyle(light: Color(red: 0xB0 / 255, green: 0x30 / 255, blue: 0), dark: .orange)
    }
    /// Text in the accent color the user picked, on its own tint (the
    /// "Recommended" `HeadingBadge`, a chosen card's included): darkened in
    /// light mode, where the system's is hard to read, enough for 4.5:1
    /// with any of macOS's accent colors.
    static var appAccent: AppearanceStyle {
        AppearanceStyle(light: Color.accentColor.mix(with: .black, by: 0.45), dark: Color.accentColor)
    }
    /// A card's background.
    static var cardFill: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.05), dark: .quaternary.opacity(0.6))
    }
    /// A card's outline: in light mode only, where the fill alone barely
    /// shows against the menu's white.
    static var cardBorder: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.1), dark: Color.clear)
    }
    /// A filled chip's background, at rest.
    static var chipFill: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.08), dark: .quaternary.opacity(0.6))
    }
    /// A chip's background under the pointer: a step above `chipFill`.
    static var chipHoverFill: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.13), dark: .quaternary)
    }
    /// Icons for what works: Diagnostics' checks.
    static var appSuccess: AppearanceStyle {
        AppearanceStyle(light: Color.green, dark: Color.green)
    }
    /// A switch's track while it's off.
    static var switchOffFill: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.26), dark: .quaternary)
    }
    /// Behind a `HeadingBadge`: `appWarning`, faint.
    static var warningBadgeFill: AppearanceStyle {
        AppearanceStyle(light: Color(red: 0xB0 / 255, green: 0x30 / 255, blue: 0).opacity(0.12), dark: Color.orange.opacity(0.18))
    }

    /// Behind a list row the user selected (Settings → Apps).
    static var selectedRowFill: AppearanceStyle {
        AppearanceStyle(light: Color.accentColor.opacity(0.14), dark: Color.accentColor.opacity(0.18))
    }

    /// Behind the chosen player's tile (`PlayerTiles`).
    static var selectedTileFill: AppearanceStyle {
        AppearanceStyle(light: Color.accentColor.opacity(0.18), dark: Color.accentColor.opacity(0.22))
    }

    /// Behind the page shown, in Settings' sidebar.
    static var sidebarSelectionFill: AppearanceStyle {
        AppearanceStyle(light: Color.black.opacity(0.1), dark: .quaternary)
    }

    /// The square behind a `SymbolTile`'s symbol (Settings' sidebar, the
    /// welcome window's permissions): the accent color the user picked,
    /// faint.
    static var symbolTileFill: AppearanceStyle {
        AppearanceStyle(light: Color.accentColor.opacity(0.16), dark: Color.accentColor.opacity(0.2))
    }
}
