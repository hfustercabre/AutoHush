/// One app's row in the menu bar's Now Playing panel (Control Center's): its
/// text ("Song, Artist – Album", or the app's name) and whether it plays.
/// The rows don't name their apps (only an icon shows it).
package struct PanelRow: Equatable, Sendable {
    package let text: String
    package let playing: Bool

    init(text: String, playing: Bool) {
        self.text = text
        self.playing = playing
    }
}
