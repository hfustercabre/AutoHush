import Foundation

/// What a panel's content was given: its size and dim callbacks.
@MainActor
final class CheckPanelCallbacks {
    var dimmed: ((Bool) -> Void)?
}
