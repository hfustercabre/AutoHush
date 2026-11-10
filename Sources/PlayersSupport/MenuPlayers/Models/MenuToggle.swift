/// The Play/Pause item of an app's playback menu: "Pause" while it plays,
/// "Play" while it's paused, in the app's language. Disabled while there's
/// nothing to play (TIDAL: nobody logged in).
package struct MenuToggle: Equatable, Sendable {
    package let title: String
    /// `nil` when it couldn't be read (the item replaced as it was read, as
    /// TIDAL rebuilds its menu bar, or the app slow to answer): that says
    /// nothing, unlike a disabled item.
    package let isEnabled: Bool?

    init(title: String, isEnabled: Bool?) {
        self.title = title
        self.isEnabled = isEnabled
    }
}
