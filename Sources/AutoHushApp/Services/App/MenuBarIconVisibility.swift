import AppKit

/// Whether AutoHush's menu bar icon can be seen, for Settings → General's
/// note (the user, 2026-10-26: AutoHush opened again opens Settings, its way
/// in when the icon is hidden). macOS doesn't say: the icon's window stays
/// "visible" wherever it is, and an app whose menus run over it doesn't hide
/// it (macOS 27 shortens the menus instead; tried in the VM, 2026-10-26).
/// What tells is where the window is: off the screen, or behind the notch,
/// between the areas macOS leaves free beside it (`auxiliaryTopLeftArea`
/// and `auxiliaryTopRightArea`, empty on a screen without one). Above the
/// screen's top doesn't count as off it: "Automatically hide and show the
/// menu bar" slides the bar's windows there while it's hidden, and the icon
/// comes back with the bar (U9, 2026-10-27).
@MainActor
enum MenuBarIconVisibility {
    /// Whether the icon in `button` is hidden now; `false` without one.
    static func isHidden(_ button: NSStatusBarButton?) -> Bool {
        guard let window = button?.window else { return false }
        guard let screen = window.screen ?? NSScreen.screens.first else { return false }
        return isHidden(icon: window.frame, isVisible: window.isVisible, screen: screen.frame,
                        leftOfNotch: screen.auxiliaryTopLeftArea?.width, rightOfNotch: screen.auxiliaryTopRightArea?.width)
    }

    /// The rule, from the window's frame and its screen's, and the widths
    /// left free each side of the notch (`nil` without a notch). By widths,
    /// so the areas' own origin doesn't matter.
    nonisolated static func isHidden(icon: CGRect, isVisible: Bool, screen: CGRect,
                                     leftOfNotch: CGFloat?, rightOfNotch: CGFloat?) -> Bool {
        guard isVisible, screen.intersects(icon) || isAboveTop(of: screen, icon) else { return true }
        guard let leftOfNotch, let rightOfNotch else { return false }
        let notch = (screen.minX + leftOfNotch)...(screen.maxX - rightOfNotch)
        return notch.contains(icon.midX)
    }

    /// Above the screen's top edge, within its width: where a hidden menu
    /// bar has slid it.
    private nonisolated static func isAboveTop(of screen: CGRect, _ icon: CGRect) -> Bool {
        icon.minY >= screen.maxY && icon.maxX > screen.minX && icon.minX < screen.maxX
    }
}
