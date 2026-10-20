import SwiftUI

/// The window states as segments (those done, the one it's in, those to
/// come), its name with "n of m", and what the check does there.
package struct CheckWindowStepView: View {
    let index: Int
    let count: Int
    let name: String
    /// "3 of 7", in the app's words.
    let stepText: String
    let activity: String
    /// What VoiceOver reads for the whole of it.
    let accessibilityText: String
    let look: CheckPanelLook

    package init(index: Int, count: Int, name: String, stepText: String, activity: String, accessibilityText: String, look: CheckPanelLook) {
        self.index = index
        self.count = count
        self.name = name
        self.stepText = stepText
        self.activity = activity
        self.accessibilityText = accessibilityText
        self.look = look
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(1...max(count, 1), id: \.self) { segment in
                    Capsule()
                        .fill(segment < index ? Color.accentColor
                              : segment == index ? Color.accentColor.opacity(0.45) : look.track)
                        .frame(height: 5)
                }
            }
            HStack {
                Text(verbatim: name).font(.callout.weight(.medium))
                Spacer()
                Text(verbatim: stepText).font(look.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(verbatim: activity).font(look.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }
}
