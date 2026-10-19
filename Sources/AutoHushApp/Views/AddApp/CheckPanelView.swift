import AppKit
import CheckedPlayers
import SwiftUI

/// The check's panel, at the bottom right of the screen on every desktop
/// while it runs (as Player Check's): the app, what the check does, Stop;
/// what it asks of the user (with the time left), or the window states as
/// segments, the one it's in and the way it's pressing; and, while the
/// mouse and keyboard are blocked, that they are (the screen dims then).
struct CheckPanelView: View {
    let model: AddAppModel
    let app: CheckableApp
    /// Its size, for the panel to fit it.
    let resized: (CGSize) -> Void
    /// Whether the screen is dimmed: while input is blocked.
    let dimmed: (Bool) -> Void
    @State private var stopping = false

    private var progress: CheckProgress { model.progress }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: AppIcon.appImage(bundlePath: app.url.path, size: 34))
                    .resizable().frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    // Two lines at most: “Deezer wird geprüft” didn't fit in one.
                    Text(verbatim: AddAppText.checking(app.name)).font(.appHeadline).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: stopping ? AddAppText.stopping : progress.request == nil ? AddAppText.stage(progress.stage) : AddAppText.waitingForYou)
                        .font(.appCaption).foregroundStyle(.appSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    stopping = true
                    model.stopCheck()
                } label: { Text(verbatim: AddAppText.stop) }
                    .buttonStyle(.chip)
                    .disabled(stopping)
            }
            if let request = progress.request {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let since = progress.requestSince ?? context.date
                    let left = Double(request.minutes * 60) - context.date.timeIntervalSince(since)
                    note(AddAppText.request(request, app: app.name), detail: AddAppText.timeLeft(left, for: request), symbol: Self.symbol(request))
                }
            } else if let step = progress.windowStep {
                windowStep(step)
            }
            if progress.blocksInput {
                Label(AddAppText.blockedNote, systemImage: "hand.raised")
                    .font(.appCallout.weight(.medium))
                    .foregroundStyle(.appWarning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.warningBadgeFill))
            }
        }
        .padding(14)
        .frame(width: 310)
        .fixedSize(horizontal: false, vertical: true)
        .font(.appBody)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { resized($0) }
        .onChange(of: progress.blocksInput, initial: true) { _, blocked in dimmed(blocked) }
        // VoiceOver hears what the check asks (it waits for the user, against
        // a time limit), and that it stops.
        .onChange(of: progress.request) { _, request in
            if let request { AccessibilityNotification.Announcement(AddAppText.request(request, app: app.name)).post() }
        }
        .onChange(of: stopping) { _, stopping in
            if stopping { AccessibilityNotification.Announcement(AddAppText.stopping).post() }
        }
    }

    private static func symbol(_ request: CheckProgress.Request) -> String {
        switch request {
        case .play: "play.circle"
        case .pause: "pause.circle"
        case .allowAccessibility: "checkmark.shield"
        }
    }

    /// What's asked of the user, tinted, with the time left under it.
    private func note(_ text: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(text, systemImage: symbol).fontWeight(.medium).foregroundStyle(.appWarning)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: detail).font(.appCaption).foregroundStyle(.appSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.warningBadgeFill))
        .accessibilityElement(children: .combine)
    }

    /// The window states as segments, the one it's in, and what it does there.
    private func windowStep(_ step: CheckProgress.WindowStep) -> some View {
        let name = step.state.map(AddAppText.stateLabel) ?? ""
        let activity = progress.activity.map(AddAppText.activity) ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(1...max(step.count, 1), id: \.self) { index in
                    Capsule()
                        .fill(index < step.index ? AnyShapeStyle(Color.accentColor)
                              : index == step.index ? AnyShapeStyle(Color.accentColor.opacity(0.45)) : AnyShapeStyle(Color.chipHoverFill))
                        .frame(height: 5)
                }
            }
            HStack {
                Text(verbatim: name).font(.appCallout.weight(.medium))
                Spacer()
                Text(verbatim: AddAppText.stepOf(step.index, step.count)).font(.appCaption).foregroundStyle(.appSecondary).monospacedDigit()
            }
            Text(verbatim: activity).font(.appCaption).foregroundStyle(.appSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [name, AddAppText.stepOf(step.index, step.count), activity].joined(separator: ", ")))
    }
}
