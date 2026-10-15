import AppKit

extension NSAppearance {
    /// Dark (Dark Aqua) rather than light.
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}
