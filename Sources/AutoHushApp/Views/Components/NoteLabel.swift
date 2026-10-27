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

    init(_ text: String, kind: Kind = .warning, font: Font = .appCallout) {
        self.text = text
        self.kind = kind
        self.font = font
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            switch kind {
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.appWarning)
            case .info:
                Image(systemName: "info.circle")
                    .foregroundStyle(.appSecondary)
            }
        }
        .font(font)
        .foregroundStyle(kind == .info ? AnyShapeStyle(.appSecondary) : AnyShapeStyle(.primary))
        .fixedSize(horizontal: false, vertical: true)
    }
}
