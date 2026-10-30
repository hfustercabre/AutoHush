import AppKit

/// A button of the app's page (a pressable item of a Flutter app's
/// interface), named by `label(of:)`, as AutoHush names it.
struct FoundButton {
    let element: AXUIElement
    let label: String
    /// Points from its middle to its window's bottom; nil without a frame.
    let fromBottom: Double?
    /// Inside its window. One scrolled out of an Electron window is squeezed
    /// to no height at the window's edge (an Electron player's song tiles), so it isn't.
    let inSight: Bool
    /// In a window on screen (`isOnScreen`), so it can be hit-tested.
    let onScreen: Bool
}
