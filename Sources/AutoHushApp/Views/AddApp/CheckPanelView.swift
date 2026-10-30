import AppKit
import CheckPanel
import CheckedPlayers
import PlayerCheckKit
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

    private var stopping: Bool { model.isStopping }

    private var progress: CheckProgress { model.progress }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: AppIcon.appImage(bundlePath: app.url.path, size: 34))
                    .resizable().frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    // Two lines at most: in German, “… wird geprüft” didn't fit in one.
                    Text(verbatim: AddAppText.checking(app.name)).font(.appHeadline).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: stopping ? AddAppText.stopping : progress.request == nil ? AddAppText.stage(progress.stage) : AddAppText.waitingForYou)
                        .font(.appCaption).foregroundStyle(.appSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button { model.stopCheck() } label: { Text(verbatim: AddAppText.stop) }
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
        .onChange(of: model.isStopping) { _, stopping in
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

    /// AutoHush's look for the parts both apps' panels draw: what the check
    /// asks in the accent color, apart from the orange warning that input is
    /// blocked, so the step to do now stands out (the user, 2026-10-21).
    private static let look = CheckPanelLook(caption: .appCaption, requestTint: .appAccent, requestFill: .nextStepFill,
                                             track: .chipHoverFill)

    /// What's asked of the user, in the accent color, with the time left under it.
    private func note(_ text: String, detail: String, symbol: String) -> some View {
        CheckRequestNote(text, detail: detail, symbol: symbol, look: Self.look)
    }

    /// The window states as segments, the one it's in, and what it does there.
    private func windowStep(_ step: CheckProgress.WindowStep) -> some View {
        let name = step.state.map(AddAppText.stateLabel) ?? ""
        // None yet with its windows closed, where nothing is moved first.
        let activity = progress.activity.map(AddAppText.activity) ?? ""
        let stepText = AddAppText.stepOf(step.index, step.count)
        return CheckWindowStepView(index: step.index, count: step.count, name: name, stepText: stepText, activity: activity,
                                   accessibilityText: [name, stepText, activity].filter { !$0.isEmpty }.joined(separator: ", "), look: Self.look)
    }
}
