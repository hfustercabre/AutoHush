import SwiftUI

extension EnvironmentValues {
    /// The keys of the window this view is in (`WindowKeys`), which its main
    /// button tells whether Return can press it (`MainButton`).
    @Entry var windowKeys: WindowKeys?
}

extension View {
    /// A guiding window's content with its keys (`WindowKeys`): their
    /// highlight for its controls (`Highlightable`), and they for its main
    /// button. `nil`: none, as before A4c.
    func windowKeys(_ keys: WindowKeys?) -> some View {
        environment(keys?.highlight).environment(\.windowKeys, keys)
    }
}
