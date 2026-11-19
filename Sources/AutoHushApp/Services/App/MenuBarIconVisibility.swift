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
        let screens = NSScreen.screens
        guard let screen = window.screen ?? screenIndex(for: window.frame, among: screens.map(\.frame)).map({ screens[$0] })
        else { return false }
        return isHidden(icon: window.frame, isVisible: window.isVisible, screen: screen.frame,
                        leftOfNotch: screen.auxiliaryTopLeftArea?.width, rightOfNotch: screen.auxiliaryTopRightArea?.width)
    }

    /// Which of the screens (their frames) the rule measures an icon
    /// against whose window macOS gives no screen, as it's off every one
    /// (above a second screen's top, its menu bar hidden: the 2026-11-19
    /// bug hunt's app-services-4): the screen it's over, the one whose top
    /// is nearest it; over none, the first.
    nonisolated static func screenIndex(for icon: CGRect, among screens: [CGRect]) -> Int? {
        let over = screens.indices.filter { screens[$0].minX <= icon.midX && icon.midX < screens[$0].maxX }
        return over.min { abs(icon.minY - screens[$0].maxY) < abs(icon.minY - screens[$1].maxY) }
            ?? (screens.isEmpty ? nil : 0)
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
