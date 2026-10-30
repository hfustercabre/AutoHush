/// What `AppDelegate` needs of the learning window; tests stand in for it,
/// so they never put a window on screen.
@MainActor
protocol LearningWindowPresenting: AnyObject {
    var isOpen: Bool { get }
    /// When it closes: Later, its close button, or once learned.
    var onClose: (@MainActor () -> Void)? { get set }
    func show()
    func close()
}
