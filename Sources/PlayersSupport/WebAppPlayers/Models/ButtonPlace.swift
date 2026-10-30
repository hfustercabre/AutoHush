import Foundation

/// Where a button is on its page, to find it again after a reload, when
/// every element is new.
package struct ButtonPlace: Codable, Equatable, Sendable {
    /// The kinds of element around it, its parent first, up to the page:
    /// e.g. "AXGroup", "AXToolbar", "AXGroup:AXLandmarkComplementary". Never
    /// their names, which are in the site's language and can change.
    package let path: [String]
    /// Points from its middle to the bottom of its window: players keep
    /// their controls at the bottom.
    package let distanceFromBottom: Double

    package init(path: [String], distanceFromBottom: Double) {
        self.path = path
        self.distanceFromBottom = distanceFromBottom
    }
}
