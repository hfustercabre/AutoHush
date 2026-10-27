import AppKit
import CheckedPlayers
import PlayerCheckKit
import SwiftUI

struct AppDetail: View {
    let app: InstalledApp
    let checker: Checker
    @State private var confirming = false
    @State private var confirmingRelaunch = false
    @State private var showsReport = false

    private var report: CheckReport? { checker.reports[app.id] }
    private var isChecking: Bool { checker.checkingID == app.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                // While a check waits for it, its own request says it instead.
                if !checker.isTrusted, !(isChecking && report?.state == .allowing) { permissionNote }
                launchOptionNote
                controls
                if checker.hasWorkingWay(app) {
                    playAndPause
                } else if checker.controllingID == app.id || checker.controls[app.id] != nil {
                    // A way's own buttons, with no way that worked to head the section.
                    pressStatus
                }
                if let report { results(report) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Check “\(app.name)”?", isPresented: $confirming) {
            Button(checker.isRunning(app) ? "Check" : "Open and Check") { checker.check(app) }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmation)
        }
        .alert("Relaunch “\(app.name)”?", isPresented: $confirmingRelaunch) {
            Button("Relaunch") { checker.relaunch(app) }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(app.name) quits and opens again with \(checker.launchOptions[app.id]?.option ?? "its launch option"), in the background."
                 + " Whatever it's playing stops.")
        }
        .task(id: checker.isRunning(app)) { checker.readLaunchOption(app) }
    }

    /// For an Electron app running without the option its page needs to take
    /// presses out of view: a warning (a check now would show those window
    /// states failing) and a button to relaunch it with it.
    @ViewBuilder private var launchOptionNote: some View {
        if let launch = checker.launchOptions[app.id], launch.running == .no || checker.relaunchingID == app.id {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(app.name) is running without Chromium's \(launch.option): its page can't be pressed while its window is covered"
                      + " or on another desktop, so a check now would show those states failing.",
                      systemImage: "exclamationmark.triangle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Relaunch \(app.name) With It") { confirmingRelaunch = true }
                        .disabled(checker.isBusy || checker.tool == nil)
                    if checker.relaunchingID == app.id {
                        ProgressView().controlSize(.small)
                        Text("Relaunching…").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        if let result = checker.relaunches[app.id], checker.relaunchingID != app.id {
            Label(result.text, systemImage: result.worked ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.worked ? .green : .red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.title2.weight(.semibold))
                Text(app.bundleID ?? "no bundle ID").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Text(app.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let reason = app.nowPlayingReason {
                    Text("Can be in Now Playing: \(reason)").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Tag(text: checker.isRunning(app) ? "Running" : "Not running", tint: checker.isRunning(app) ? .green : .secondary)
                    if let client = checker.client(of: app) { Tag(text: client.summary, tint: .pink) }
                    if app.isSafariWebApp { Tag(text: "Safari web app", tint: .blue) }
                    if let interface = app.hiddenInterface { Tag(text: interface, tint: .purple) }
                }
                .padding(.top, 2)
            }
        }
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Privacy & Security at a permission's list (Audio Recording is under
    /// Screen & System Audio Recording).
    static func openPrivacySettings(for permission: CheckReportLine.Permission) {
        let pane = switch permission {
        case .accessibility: "Privacy_Accessibility"
        case .audioRecording: "Privacy_ScreenCapture"
        case .automation: "Privacy_Automation"
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    private var permissionNote: some View {
        GroupBox {
            HStack {
                Label("Player Check needs the Accessibility permission to read menus and pages.", systemImage: "exclamationmark.triangle")
                Spacer()
                Button("Open Settings") { Self.openAccessibilitySettings() }
            }
            .padding(4)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(report == nil ? "Check…" : "Check Again…") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(checker.isBusy || checker.tool == nil)
                if isChecking {
                    Button("Stop") { checker.stop() }
                    ProgressView().controlSize(.small)
                    Text(report?.state == .allowing ? "Waiting for the Accessibility permission…"
                         : report?.state == .opening ? "Opening \(app.name)…" : report?.request != nil ? "Waiting for you…"
                         : report?.windowState.map { state in
                             // "its window covered, 2 of 7"; "its windows closed, 1 of 1".
                             "Checking: its \(report?.testedState?.state == .windowsClosed ? "" : "window ")\(state)…"
                         } ?? "Checking…")
                        .foregroundStyle(.secondary)
                }
            }
            if isChecking, report?.state == .allowing {
                // Asked of macOS: the check starts by itself once it's allowed.
                VStack(alignment: .leading, spacing: 8) {
                    // Not named by its pane: macOS 27 calls it Device Control and Data Access.
                    Label("Turn on Player Check in the list System Settings opens (macOS's request leads there, or the button below). The check starts as soon as it's allowed.",
                          systemImage: "hand.raised")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open System Settings") { Self.openAccessibilitySettings() }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            if isChecking, let request = report?.request {
                // The test needs the app playing: the check asks, then goes on by itself.
                Label(request, systemImage: "play.circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isChecking, let problem = checker.permissionProblems[app.id] {
                // Cancelled before it did anything (no window moved, nothing pressed).
                VStack(alignment: .leading, spacing: 8) {
                    Label("The check was cancelled before it did anything: \(problem.text)", systemImage: "exclamationmark.triangle")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if let missing = problem.missing {
                        Button("Open System Settings") { Self.openPrivacySettings(for: missing) }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            if checker.tool == nil {
                Text("playercheck is missing from this app: build it with build.sh.").foregroundStyle(.red)
            }
        }
    }

    /// Play and Pause, by the first way that worked in its check with the
    /// app's window in the state it's in when pressed, alone.
    private var playAndPause: some View {
        let running = checker.isRunning(app)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Play and Pause").font(.headline)
            HStack {
                Button { checker.controlByState(app, .play) } label: { Label("Play", systemImage: "play.fill") }
                Button { checker.controlByState(app, .pause) } label: { Label("Pause", systemImage: "pause.fill") }
            }
            .disabled(checker.isBusy || !running || checker.tool == nil)
            Text(!running ? "Open it first: it isn't running."
                 : "By the first way that worked in its check with its window as it is when pressed (covered, minimized, …).")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            pressStatus
        }
    }

    /// A Play or Pause of this app: running (with Stop), else its result.
    @ViewBuilder private var pressStatus: some View {
        if checker.controllingID == app.id {
            HStack {
                ProgressView().controlSize(.small)
                Text(checker.controls[app.id]?.text ?? "…").foregroundStyle(.secondary)
                Button("Stop") { checker.stopPress() }
            }
        } else if let result = checker.controls[app.id], let worked = result.worked {
            Label(result.text, systemImage: worked ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(worked ? .green : .red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    nonisolated static func wayName(_ way: CheckResult.WayKind) -> String {
        switch way {
        case .script: "AppleScript"
        case .menu: "its playback menu"
        case .page: "its page's button"
        case .panel: "its row in the Now Playing panel"
        }
    }

    private var confirmation: String {
        var parts: [String] = []
        if !checker.isTrusted {
            parts.append("It needs the Accessibility permission first: macOS asks for it, and the check starts once it's allowed.")
        }
        if !checker.isRunning(app) { parts.append("It isn't running: Player Check opens it first, in the background.") }
        parts.append("Before anything else, it makes sure Player Check has every permission a check needs: Accessibility, Audio Recording, and Automation for \(app.name) if it can be scripted; macOS asks for any not decided yet, and without all of them the check is cancelled before it does anything.")
        if let browser = app.webAppBrowser {
            parts.append("\(browser) is muted all through the check, its other tabs and web apps too (a call in it as well), and heard again at the end.")
        } else {
            parts.append("\(app.name) is muted all through the check (you won't hear it; Player Check still hears whether it plays) and heard again at the end.")
        }
        parts.append("It reads its scripting dictionary, its menus, its sound and Now Playing, and its page's buttons if it shows a page.")
        parts.append("Before it moves anything, \(app.name) must be playing: if it isn't, you're asked to start it, and the check waits up to 2 minutes.")
        parts.append("Then it tests each way to control it: it pauses \(app.name) and plays it again by each, the menu bar's Now Playing panel included (it shows for a moment).")
        parts.append("It does so with \(app.name)'s window in each state: visible, covered (Player Check puts a window over it), on another desktop, covered there, full screen, minimized and hidden. Player Check moves the window there itself and comes back to the front each time; for the desktops it drags the window with the pointer and Control-arrow, so from the first move until the window is put back your clicks, scrolling and keys are blocked (the pointer still moves, except during a drag) and the screen dims, apart from the panel. The panel's Stop and Escape still work, and stop the check; whenever the check asks you something, they're all yours again. Player Check's own window may move aside. Everything is put back as it was at the end. It takes about 3 minutes.")
        parts.append("A small panel at the bottom right of the screen shows how far it has got, with Stop, on every desktop.")
        if let launch = checker.launchOptions[app.id], launch.running == .no {
            parts.append("\(app.name) is running without \(launch.option): its page's presses may fail while its window is covered or on another desktop.")
        }
        if let note = app.switchNote { parts.append(note) }
        return parts.joined(separator: " ")
    }

    @ViewBuilder private func results(_ report: CheckReport) -> some View {
        if let note = checker.attemptNotes[app.id] {
            Label(note, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
        }
        if case .failed(let reason) = report.state, checker.permissionProblems[app.id] == nil {
            Label(reason, systemImage: "xmark.octagon").foregroundStyle(.red)
        } else if report.state == .stopped {
            Label("Stopped: the report is incomplete.", systemImage: "stop.circle").foregroundStyle(.secondary)
        }
        let ways = report.ways
        if !ways.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ways to Control It").font(.headline)
                ForEach(ways) { way in
                    // Each way's own buttons use that way alone.
                    let usable = way.canControl && checker.isRunning(app) && report.state == .finished
                    WayRow(way: way, control: usable ? way.via.map { via in { checker.control(app, $0, via: via) } } : nil,
                           isBusy: checker.isBusy)
                }
                Text("✓ worked in every window state  ·  ⚠ in some  ·  ✗ in none, or not there  ·  ? not tried  ·  – not checked")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        if !report.verdict.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("For AutoHush").font(.headline)
                Text(report.verdict).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
        if report.state == .finished {
            Text("Checked \(report.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
        }
        DisclosureGroup(isExpanded: Binding(get: { showsReport || (isChecking && ways.isEmpty) }, set: { showsReport = $0 })) {
            VStack(alignment: .trailing, spacing: 6) {
                Text(report.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                Button("Copy Report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.text, forType: .string)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Full report").font(.headline)
        }
    }
}
