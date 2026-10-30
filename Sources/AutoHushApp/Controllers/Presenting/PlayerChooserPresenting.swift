/// What `AppDelegate` needs of the welcome window; tests stand in for it, so
/// they never put a window on screen.
@MainActor
protocol PlayerChooserPresenting: AnyObject {
    var isOpen: Bool { get }
    func show()
    func bringForward()
    func close()
}
