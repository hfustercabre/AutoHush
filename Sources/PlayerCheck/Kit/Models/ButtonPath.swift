/// Where a player bar's button sits: the child indices from its page (an
/// AXWebArea) or, in a Flutter app, its window, down to it, so a press walks
/// straight to it instead of searching the page and hit-testing its buttons.
package struct ButtonPath: Codable, Equatable, Sendable {
    package enum Root: String, Codable, Sendable { case page, window }
    package var root: Root
    package var path: [Int]

    package init(root: Root, path: [Int]) {
        self.root = root
        self.path = path
    }
}
