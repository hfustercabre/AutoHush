import CoreGraphics
import Foundation
@testable import AutoHushApp

/// A menu-like layout: a title, five durations in a row, four buttons in a row.
@MainActor
enum MenuLikeRows {
    static func make() -> (k: KeyHighlight, title: UUID, chips: [UUID], toolbar: [UUID]) {
        let k = KeyHighlight()
        let title = UUID()
        k.register(title, .init(frame: CGRect(x: 0, y: 0, width: 345, height: 20)))
        let chips = (0..<5).map { i -> UUID in
            let id = UUID()
            k.register(id, .init(frame: CGRect(x: 14 + CGFloat(i) * 65, y: 40, width: 60, height: 30)))
            return id
        }
        let toolbar = (0..<4).map { i -> UUID in
            let id = UUID()
            k.register(id, .init(frame: CGRect(x: 8 + CGFloat(i) * 82, y: 100, width: 80, height: 40)))
            return id
        }
        return (k, title, chips, toolbar)
    }
}
