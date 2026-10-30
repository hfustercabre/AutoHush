import Foundation

/// A button as one look at a page found it.
package struct PageButton: Equatable, Sendable {
    package let handle: ButtonHandle
    /// What it says to VoiceOver, e.g. "Pause" or "Play Discover Weekly", in
    /// the site's language.
    package let label: String
    let isEnabled: Bool

    package init(handle: ButtonHandle, label: String, isEnabled: Bool = true) {
        self.handle = handle
        self.label = label
        self.isEnabled = isEnabled
    }
}
