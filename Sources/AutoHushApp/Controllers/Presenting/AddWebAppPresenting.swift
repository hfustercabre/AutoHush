import Foundation

/// What Add a Web App (`AddWebAppFeature`) needs of its window; tests stand
/// in for it.
@MainActor
protocol AddWebAppPresenting: AnyObject {
    var isOpen: Bool { get }
    func show()
    func close()
    /// Off another app's dialog at `obstacle` (from the main screen's top
    /// left corner) while it shows (`HostedWindowController.moveAside`).
    func moveAside(of obstacle: CGRect)
    /// Back where it was before `moveAside`, unless the user moved it.
    func returnFromAside()
}
