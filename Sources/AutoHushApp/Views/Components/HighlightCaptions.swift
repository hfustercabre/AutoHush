import SwiftUI

extension View {
    /// `reason` shows while the keys' highlight is on this control (A13a,
    /// the user's pick, 2026-11-01: what only a help tag said, for the
    /// keyboard); dimmed, the keys still stop on it for that. `nil`: none.
    /// Shown by a `HighlightReasonCaption` around it, or read inside it
    /// (`keyHighlightByKeys`, a menu row).
    func highlightReason(_ reason: String?) -> some View {
        environment(\.highlightReason, reason)
    }
}

/// The reason of the control the keys' highlight is on, from inside a view
/// (`highlightReason(_:)`).
struct ShownHighlightReason: PreferenceKey {
    static let defaultValue: String? = nil

    static func reduce(value: inout String?, nextValue: () -> String?) {
        value = value ?? nextValue()
    }
}

/// `text` as a caption while the keys' highlight is on the row it's in
/// (A13a): what a row's control does, which its help tag says to the pointer.
struct KeyHighlightCaption: View {
    let text: String
    @Environment(\.keyHighlightByKeys) private var byKeys

    var body: some View {
        if byKeys { Text(verbatim: text).captionStyle() }
    }
}

/// `content`, then the reason of the control in it the keys' highlight is
/// on, if any, as a caption under it (A13a).
struct HighlightReasonCaption<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var reason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if let reason { Text(verbatim: reason).captionStyle() }
        }
        .onPreferenceChange(ShownHighlightReason.self) { shown in
            MainActor.assumeIsolated { reason = shown }
        }
    }
}
