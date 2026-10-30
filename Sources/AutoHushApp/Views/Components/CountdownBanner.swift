import SwiftUI

/// How long is left to do a step, as a sentence on an orange-tinted line
/// with a timer, so it stands out among the step's grey lines.
struct CountdownBanner: View {
    let text: String

    var body: some View {
        Label {
            Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "timer")
        }
        .font(.appCallout.weight(.semibold))
        .foregroundStyle(.appWarning)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.warningBadgeFill))
        .padding(.vertical, 2)
    }
}
