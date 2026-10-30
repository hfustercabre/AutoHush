/// How the page was found.
@MainActor enum PageState {
    /// The switch that showed the page; nil when it showed without one.
    static var shownBySwitch: String?
    /// Whether the page was read: a press by the panel reads it only when
    /// its row can't be told otherwise (`panelPress`).
    static var read = false
    /// Set by a press when its page didn't show with the switch on: an
    /// Electron, CEF or Flutter app builds it only while its window can be
    /// seen, and a press doesn't bring it forward.
    static var outOfView = false
}
