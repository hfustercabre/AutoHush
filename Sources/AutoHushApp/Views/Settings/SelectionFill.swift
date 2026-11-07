import SwiftUI

/// A selected Sound Sources row's ground: macOS's selection color; where
/// the keys' highlight is, outlined inside in white, as the highlight's
/// accent outline, behind it, doesn't show (A1a, A2a).
struct SelectionFill: View {
    @Environment(\.keyHighlightByKeys) private var byKeys

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        shape
            .fill(.listSelectionFill)
            .overlay { if byKeys { shape.strokeBorder(.onSelection, lineWidth: 2) } }
    }
}
