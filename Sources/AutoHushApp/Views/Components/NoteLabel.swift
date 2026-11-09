import SwiftUI

/// A short note with an icon, in Settings and the welcome window: a warning
/// (orange triangle) or plain information.
struct NoteLabel: View {
    enum Kind {
        case warning, info
    }

    /// Already localized.
    let text: String
    let kind: Kind
    /// `appCallout`, or the notes' `appCaption` under a row's title (Add an
    /// App's recommended way, U1, 2026-10-27).
    let font: Font
    /// On a chosen card's selection color: white, its symbol too, as a
    /// selected list row draws its symbols (KB2a, the a11y audit's KB2, the
    /// user's pick, 2026-11-06).
    let onSelection: Bool

    init(_ text: String, kind: Kind = .warning, font: Font = .appCallout, onSelection: Bool = false) {
        self.text = text
        self.kind = kind
        self.font = font
        self.onSelection = onSelection
    }

    var body: some View {
        Label {
            Text(verbatim: text)
        } icon: {
            switch kind {
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(onSelection ? AnyShapeStyle(.onSelection) : AnyShapeStyle(.appWarning))
            case .info:
                Image(systemName: "info.circle")
                    .foregroundStyle(onSelection ? AnyShapeStyle(.onSelection) : AnyShapeStyle(.appSecondary))
            }
        }
        .font(font)
        .foregroundStyle(onSelection ? AnyShapeStyle(.onSelection) : kind == .info ? AnyShapeStyle(.appSecondary) : AnyShapeStyle(.primary))
        .fixedSize(horizontal: false, vertical: true)
    }
}
