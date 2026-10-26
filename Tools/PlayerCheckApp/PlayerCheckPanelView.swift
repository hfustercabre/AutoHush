import AppKit
import CheckPanel
import CheckedPlayers
import PlayerCheckKit
import SwiftUI

/// What the check's panel shows (`CheckPanelController`, as AutoHush's: a
/// small panel at the bottom right of the screen while the check runs, on
/// every desktop, full screen apps' too, and a shade dimming every screen
/// but it while playercheck blocks the mouse and keyboard): the app, what
/// the check is doing, Stop; what it asks of you (with the time left), or
/// the window states as segments (each one filled once tested), the one
/// it's in and the way it's pressing; and, while the mouse and keyboard are
/// blocked, that they are.
struct CheckPanelView: View {
    let app: InstalledApp
    let checker: Checker
    /// Its size, for the panel to fit it.
    let resized: (CGSize) -> Void
    /// Whether the screen is dimmed: while input is blocked.
    let dimmed: (Bool) -> Void

    private var report: Report? { checker.reports[app.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable().frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Checking \(app.name)").font(.headline).lineLimit(1)
                    Text(stage).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Stop") { checker.stop() }
                    .disabled(report?.state == .stopped)
            }
            if let request = report?.request {
                requestNote(request)
            } else if report?.state == .allowing {
                note("Turn on Player Check in the list System Settings opens", detail: "The check starts as soon as it's allowed.",
                     systemImage: "checkmark.shield")
            } else if let step = report?.testedState {
                progress(step)
            }
            if inputBlocked {
                // As the window's warnings: the check drags windows with the pointer.
                Label("Clicks, scrolling and keys are blocked until it ends. Stop or Escape ends the check.", systemImage: "hand.raised")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .frame(width: 310)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { resized($0) }
        .onChange(of: inputBlocked, initial: true) { _, blocked in dimmed(blocked) }
    }

    /// What the check is doing, by the report's section.
    private var stage: String {
        guard let report else { return "" }
        switch report.state {
        case .allowing: return "Waiting for the Accessibility permission"
        case .opening: return "Opening \(app.name)…"
        case .stopped: return "Stopping: putting everything back as it was…"
        case .finished, .failed: return ""
        case .checking: break
        }
        if report.request != nil { return "Waiting for you" }
        switch report.progress.stage {
        case .permissions: return "Checking permissions"
        case .playing: return "Checking that it plays"
        case .movingWindow: return "Moving its window to where the test starts"
        case .readingPage: return "Reading its page"
        case .testing: return "Testing its window states"
        case .finishing: return "Writing the report"
        case .reading: return "Reading its dictionary, menus and sound"
        }
    }

    /// From playercheck's "blocked" line until it says they're free again,
    /// a stop's put-back included; not while it asks something of you,
    /// when it lifts the block.
    private var inputBlocked: Bool {
        guard let report, report.state == .checking || report.state == .stopped else { return false }
        return report.progress.blocksInput
    }

    /// The request ("start playing something in <app>; the test goes on …
    /// (up to 2 minutes). …"): what's asked, then the rest with the time left.
    private func requestNote(_ request: String) -> some View {
        let cut = [request.range(of: "; "), request.range(of: ": ")].compactMap { $0 }.min { $0.lowerBound < $1.lowerBound }
        let asked = cut.map { String(request[..<$0.lowerBound]) } ?? request
        var rest = cut.map { String(request[$0.upperBound...]) } ?? ""
        if !rest.isEmpty { rest = rest.prefix(1).uppercased() + rest.dropFirst() + (rest.hasSuffix(".") ? "" : ".") }
        let symbol = asked.hasPrefix("Pause") ? "pause.circle" : asked.hasPrefix("Allow") ? "checkmark.shield" : "play.circle"
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            note(asked, detail: Self.withTimeLeft(rest, since: report?.progress.requestSince, now: context.date), systemImage: symbol)
        }
    }

    /// "(up to 2 minutes)" as the time left since the request came ("(1:48 left)").
    static func withTimeLeft(_ text: String, since: Date?, now: Date) -> String {
        guard let since, let start = text.range(of: "up to "),
              let unit = text.range(of: " minute", range: start.upperBound..<text.endIndex),
              let minutes = Int(text[start.upperBound..<unit.lowerBound]) else { return text }
        let end = text[unit.upperBound...].hasPrefix("s") ? text.index(after: unit.upperBound) : unit.upperBound
        let left = max(0, Int(since.addingTimeInterval(Double(minutes * 60)).timeIntervalSince(now).rounded()))
        return text.replacingCharacters(in: start.lowerBound..<end, with: String(format: "%d:%02d left", left / 60, left % 60))
    }

    /// Player Check's look for the parts both apps' panels draw.
    private static let look = CheckPanelLook(caption: .caption, requestTint: .accentColor, requestFill: .accentColor.opacity(0.15),
                                             track: .secondary.opacity(0.22))

    /// The main window's note in the accent color: what's asked of you, and more under it.
    private func note(_ text: String, detail: String, systemImage: String) -> some View {
        CheckRequestNote(text, detail: detail, symbol: systemImage, look: Self.look)
    }

    /// The window states as segments, the one it's in, and what it does there.
    private func progress(_ step: CheckProgress.WindowStep) -> some View {
        let title = step.state?.title ?? ""
        let activity = report?.stateActivity ?? ""
        return CheckWindowStepView(index: step.index, count: step.count, name: title.prefix(1).uppercased() + title.dropFirst(),
                                   stepText: "\(step.index) of \(step.count)", activity: activity,
                                   accessibilityText: "Window state \(step.index) of \(step.count): \(title). \(activity)", look: Self.look)
    }
}
