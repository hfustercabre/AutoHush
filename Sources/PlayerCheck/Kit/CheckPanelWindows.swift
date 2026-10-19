import CoreGraphics
import Foundation

/// The windows of the check's panel among those on screen, which the input
/// block lets clicks through (its Stop): those of the app running the check
/// at the panel's levels only, floating, or two above pop-up menus while the
/// screen is dimmed (AutoHush's and the Player Check app's, both
/// `CheckPanelController`), and never one covering a whole display (the
/// shade). The app's menu bar icon (at the status level) and its menu
/// (pop-up menus') stay blocked.
package enum CheckPanelWindows {
    /// The panel's level while the screen isn't dimmed: it floats, under
    /// menus and the Dock.
    package static let floatingLevel = Int(CGWindowLevelForKey(.floatingWindow))
    /// The shade's level: above the menu bar, the Dock and Control Center's
    /// panels (the Now Playing panel a check opens), so it dims them all.
    package static let shadeLevel = Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1
    /// The panel's level while the screen is dimmed: above the shade.
    package static let dimmedLevel = Int(CGWindowLevelForKey(.popUpMenuWindow)) + 2
    package static let levels: Set<Int> = [floatingLevel, dimmedLevel]

    /// The frames of the panel's windows in `windows` (as
    /// `CGWindowListCopyWindowInfo` lists them), `parent`'s, among `screens`.
    package static func frames(in windows: [[String: Any]], ownedBy parent: pid_t, screens: [CGRect]) -> [CGRect] {
        windows.compactMap { info -> CGRect? in
            guard (info[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) }) == parent,
                  levels.contains(info[kCGWindowLayer as String] as? Int ?? 0),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  !screens.contains(where: { $0.size == frame.size }) else { return nil }
            return frame
        }
    }
}
