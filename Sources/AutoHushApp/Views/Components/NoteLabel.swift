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

    init(_ text: String, kind: Kind = .warning) {
        self.text = text
        self.kind = kind
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
        .font(.appCallout)
        .foregroundStyle(kind == .info ? AnyShapeStyle(.appSecondary) : AnyShapeStyle(.primary))
        .fixedSize(horizontal: false, vertical: true)
    }
}
