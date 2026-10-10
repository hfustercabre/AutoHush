import AppKit
import SwiftUI
import AutoHushKit

// "Add a Web App…", in the menu's players, Settings → General and the
// welcome window (the last tile, "Add…"): the user pastes a
// website's address, AutoHush opens it in Safari and, once the site shows
// and the user clicks Add to Dock, makes it a Safari web app (Safari's own
// Add to Dock), chooses it, opens it and learns its controls, ticking each
// step in one window.

/// How adding a web app goes, for its window.
@MainActor
@Observable
final class AddWebAppModel {
    enum Phase: Equatable {
        /// The user types or pastes the address.
        case entering
        case checking
        case opening
        /// Safari shows another site first (`shown`), asking something: the
        /// user answers it there, until `site` shows.
        case siteAsks(shown: String, site: String)
        /// `site` shows in Safari: it waits for the user's Add to Dock.
        case readyToAdd(site: String)
        case adding
        /// The web app is the player; AutoHush learns it (or already knows it).
        case learning(name: String, alreadyThere: Bool)
    }

    var address = ""
    /// A music website's address, shown as an example (the player catalog's).
    var exampleAddress: String?
    private(set) var phase = Phase.entering
    /// Why the last try failed; shown under the field.
    private(set) var problem: WebAppMakingError?
    /// The site asked something first, on this try: the step that said so
    /// stays, ticked.
    private(set) var siteAsked = false
    /// Safari's Add to Dock dialog was closed without adding: the Add to
    /// Dock step says so, until it's opened again.
    private(set) var closedWithoutAdding = false
    /// Resumed by Add to Dock (`true`), or once the add is cancelled.
    @ObservationIgnored private var addConfirmation: CheckedContinuation<Bool, Never>?
    /// The `attempt` of the add waiting in `addConfirmation`.
    @ObservationIgnored private var addConfirmationAttempt: Int?

    @ObservationIgnored var start: @MainActor (String) -> Void = { _ in }
    /// Stops the add under way.
    @ObservationIgnored var cancel: @MainActor () -> Void = {}
    /// Counts the adds started, so steps a cancelled one reports later are
    /// told apart.
    @ObservationIgnored var attempt = 0
    @ObservationIgnored var openAccessibilitySettings: @MainActor () -> Void = {}

    /// The address is being checked, opened or added in Safari.
    var isAdding: Bool {
        switch phase {
        case .checking, .opening, .siteAsks, .readyToAdd, .adding: true
        case .entering, .learning: false
        }
    }

    /// Whether what's typed can be tried: something that could be an address.
    var canContinue: Bool {
        phase == .entering && !address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Ready for an address: `address`, or none.
    func reset(address: String = "") {
        self.address = address
        phase = .entering
        problem = nil
        siteAsked = false
        closedWithoutAdding = false
        resumeAdd(false)
    }

    func continueTapped() {
        guard canContinue else { return }
        problem = nil
        siteAsked = false
        closedWithoutAdding = false
        phase = .checking
        start(address)
    }

    /// Waits for the user to click Add to Dock in the add of `attempt`:
    /// `false` once that add is cancelled instead, or at once when a newer
    /// add has started since.
    func waitForAdd(attempt: Int) async -> Bool {
        guard attempt == self.attempt else { return false }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                addConfirmation?.resume(returning: false)
                addConfirmation = continuation
                addConfirmationAttempt = attempt
            }
        } onCancel: {
            Task { @MainActor in self.cancelWait(attempt: attempt) }
        }
    }

    /// The add of `attempt` was cancelled: its wait for Add to Dock ends,
    /// unless a newer add is the one waiting by now.
    func cancelWait(attempt: Int) {
        guard addConfirmationAttempt == attempt else { return }
        resumeAdd(false)
    }

    /// Add to Dock, once the site shows.
    func addTapped() {
        guard case .readyToAdd = phase else { return }
        phase = .adding
        resumeAdd(true)
    }

    private func resumeAdd(_ add: Bool) {
        addConfirmation?.resume(returning: add)
        addConfirmation = nil
        addConfirmationAttempt = nil
    }

    /// The window closed: an add under way stops (Safari's dialog is
    /// cancelled, nothing is added). Once the web app is made, its controls
    /// can be learned later, from the Controls row of the menu's card and
    /// of Settings.
    func windowClosed() {
        guard isAdding else { return }
        cancel()
        reset()
    }

    func apply(_ step: WebAppMakingStep) {
        guard phase != .entering else { return } // a step reported after it was cancelled
        switch step {
        case .checked:                  phase = .opening
        case .opened:                   break
        case .siteAsks(let shown, let site):
            siteAsked = true
            phase = .siteAsks(shown: shown, site: site)
        case .readyToAdd(let site):     phase = .readyToAdd(site: site)
        case .adding:
            closedWithoutAdding = false
            phase = .adding
        case .notAdded:                 closedWithoutAdding = true
        case .made(let app):
            closedWithoutAdding = false
            phase = .learning(name: app.name, alreadyThere: app.alreadyThere)
        }
    }

    func fail(_ error: WebAppMakingError) {
        problem = error
        phase = .entering
        resumeAdd(false)
    }

    /// The problem in words.
    var problemText: String? {
        switch problem {
        case .notAWebAddress?:
            if let example = exampleAddress {
                String(localized: "That isn't a web address. Try one like \(example).",
                       comment: "Add a Web App window, under the address field; %@ is a music website's address, e.g. music.youtube.com")
            } else {
                String(localized: "That isn't a web address.", comment: "Add a Web App window, under the address field")
            }
        case .noAnswer(let host)?:
            String(localized: "\(host) doesn't answer. Check the address and your connection.",
                   comment: "Add a Web App window; %@ is the website, e.g. music.youtube.com")
        case .pageNotFound(let host)?:
            String(localized: "\(host) says this page doesn't exist. Check the address.",
                   comment: "Add a Web App window; %@ is the website, e.g. music.youtube.com")
        case .accessibilityDenied?:
            String(localized: "AutoHush needs Accessibility access to add it with Safari.",
                   comment: "Add a Web App window, when the Accessibility permission is missing")
        case .browserFailed?:
            String(localized: "Safari didn't add it. Try again.", comment: "Add a Web App window, when Safari didn't make the web app")
        case nil:
            nil
        }
    }
}

/// What `AppDelegate` needs of the window; tests stand in for it.
@MainActor
protocol AddWebAppPresenting: AnyObject {
    var isVisible: Bool { get }
    func show()
    func close()
}

@MainActor
final class AddWebAppWindowController: HostedWindowController, AddWebAppPresenting, NSWindowDelegate {
    private let model: AddWebAppModel

    init(model: AddWebAppModel, settings: SettingsModel) {
        self.model = model
        let hosting = Self.sizedToFit(AddWebAppView(model: model, settings: settings, close: {}))
        super.init(content: hosting,
                   title: String(localized: "Add a Web App", comment: "Title of the window that makes a website a Safari web app, in its title bar"))
        window?.delegate = self
        floatsInCorner = true // Safari, then the web app, come in front meanwhile
        hosting.rootView = AddWebAppView(model: model, settings: settings) { [weak self] in self?.close() }
    }

    /// Closing it (Cancel, Later or its close button) stops an add under way.
    func windowWillClose(_ notification: Notification) {
        model.windowClosed()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// The window's content: what it's for, the address, then each step, and
/// its buttons at the foot.
struct AddWebAppView: View {
    let model: AddWebAppModel
    /// For the learning that follows (the chosen player's status).
    let settings: SettingsModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                WindowHeader(icon: Self.safariIcon,
                             description: Text("Paste the address of a website that plays music, podcasts or videos. AutoHush opens it in Safari, adds it to your Dock as an app, and learns its controls.",
                                               comment: "Add a Web App window, at its top beside Safari's icon"))
                NoteLabel(PlayerOption.webAppsWarning)
                    .padding(.top, 8)
                // Adding drives Safari through Accessibility: without it, the
                // window says so first, and Continue waits until it's allowed.
                if needsAccessibility {
                    VStack(alignment: .leading, spacing: 8) {
                        NoteLabel(String(localized: "AutoHush needs Accessibility access to add it with Safari. Continue unlocks once it’s allowed.",
                                         comment: "Add a Web App window, while the Accessibility permission is missing"))
                        PermissionButton(model: settings, permission: Self.safariAccess, access: .denied, long: true)
                    }
                }
                SectionHeading(Text("Address", comment: "Add a Web App window: the heading over the field for the website's address"))
                    .padding(.top, 8)
                Card { addressField }
                if let problem = model.problemText, !(needsAccessibility && model.problem == .accessibilityDenied) {
                    NoteLabel(problem)
                    if model.problem == .accessibilityDenied {
                        Button(Self.safariAccess.grantTitle) { model.openAccessibilitySettings() }
                            .buttonStyle(.chip)
                    }
                }
                if model.phase != .entering {
                    SectionHeading(Self.stepsHeading).padding(.top, 8)
                    Card { steps }
                }
            }
            .windowMargins()
            BottomBar(margin: HostedWindowController.margin) {
                Spacer()
                Button { close() } label: {
                    if case .learning = model.phase {
                        // The web app is added: its controls can be learned
                        // later, from the menu's or Settings' Controls row.
                        Text("Later", comment: "Button that closes it for now: an update alert, or a window that learns a web app's controls (the learning window, the Add a Web App window)")
                    } else {
                        Text("Cancel", comment: "Add a Web App window: stops adding the website and closes the window")
                    }
                }
                .buttonStyle(.chip)
                .keyboardShortcut(.cancelAction)
                if model.phase == .entering {
                    Button { model.continueTapped() } label: {
                        Text("Continue", comment: "Button in the welcome window and the Add a Web App window: goes on with what's chosen or typed").font(.appBody.weight(.semibold)).padding(.horizontal, 6)
                    }
                    .buttonStyle(ChipButtonStyle(filled: true, isSelected: true, padded: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canContinue || needsAccessibility)
                }
            }
        }
        .frame(width: 440)
        .font(.appBody)
    }

    /// Over the card of steps, here and in the learning window.
    static var stepsHeading: Text {
        Text("Steps", comment: "Add a Web App and learning windows: the heading over the steps of adding a web app and learning its controls")
    }

    /// Accessibility, which adding needs, is missing while an address is typed.
    private var needsAccessibility: Bool {
        model.phase == .entering && !settings.permissions.accessibility
    }

    private static let safariAccess = Permission.accessibility(player: "Safari")

    private var addressField: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .foregroundStyle(.appSecondary)
                .accessibilityHidden(true)
            TextField(text: Binding(get: { model.address }, set: { model.address = $0 })) {
                Text(verbatim: model.exampleAddress ?? "")
            }
            .textFieldStyle(.plain)
            .disabled(model.phase != .entering)
            .onSubmit { if !needsAccessibility { model.continueTapped() } } // Return, as Continue
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(.chipFill))
    }

    // MARK: - The steps

    @ViewBuilder private var steps: some View {
        if let deadline = settings.learningPauseDeadline, case .learning(hasPlayed: true)? = settings.learning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                stepList(remaining: max(0, deadline.timeIntervalSince(context.date)))
            }
        } else {
            stepList(remaining: nil)
        }
    }

    private func stepList(remaining: TimeInterval?) -> some View {
        let locked = learningLocked
        let steps = Self.steps(for: model.phase, siteAsked: model.siteAsked, closedWithoutAdding: model.closedWithoutAdding,
                               learning: settings.learning,
                               remaining: remaining, note: settings.learningNote, pauseMode: settings.learningPauseMode,
                               locked: locked)
        // Locked, the permission comes right above the two learning steps it
        // unlocks.
        let before = locked ? Array(steps.dropLast(2)) : steps
        let after = locked ? Array(steps.suffix(2)) : []
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(before, id: \.title) { step($0, locked: false) }
            if locked, let control = settings.permissions.control, case .learning(let name, _) = model.phase {
                LearningPermissionStep(model: settings, permission: control, access: settings.permissions.controlAccess, name: name)
                ForEach(after, id: \.title) { step($0, locked: true) }
            }
        }
        .announcesCurrentStep(steps.currentAnnouncement)
    }

    /// Once the web app is chosen, learning it needs its control permission
    /// (Accessibility): without it, the learning steps wait, locked.
    private var learningLocked: Bool {
        guard case .learning = model.phase else { return false }
        let state = settings.permissions
        return state.control != nil && !state.controlAccess.isSatisfied
    }

    /// Each step of adding `phase`'s web app and learning it, with where it
    /// stands: “Answer the site in Safari” only once the site asked
    /// something first (`siteAsked`); `learning` is the chosen player's
    /// learning, once it's made, with the countdown and note of its steps.
    static func steps(for phase: AddWebAppModel.Phase, siteAsked: Bool = false, closedWithoutAdding: Bool = false,
                      learning: LearningStatus?,
                      remaining: TimeInterval? = nil, note: LearningNote? = nil,
                      pauseMode: LearningPauseMode = .automatic, locked: Bool = false) -> [ChecklistStep] {
        let check = ChecklistStep(title: String(localized: "Check the address", comment: "Add a Web App window: a step"),
                                  state: phase == .checking ? .current : .done)
        let opened = ChecklistStep(title: openStep, state: .done)
        let answered = siteAsked ? [ChecklistStep(title: answerStep, state: .done)] : []
        let learnLater = ChecklistStep(title: learnStepTitle, state: .todo)
        switch phase {
        case .learning(let name, true):
            return [check,
                    ChecklistStep(title: String(localized: "Already in your Dock as “\(name)”",
                                                comment: "Add a Web App window: a step, when the website already has a web app; %@ is its name"),
                                  state: .done)]
                + learningSteps(name, learning: learning, remaining: remaining, note: note, pauseMode: pauseMode, locked: locked)
        case .learning(let name, false):
            return [check, opened] + answered
                + [ChecklistStep(title: String(localized: "Add it to the Dock as “\(name)”",
                                               comment: "Add a Web App window: a step done; %@ is the web app's name"),
                                 state: .done)]
                + learningSteps(name, learning: learning, remaining: remaining, note: note, pauseMode: pauseMode, locked: locked)
        case .siteAsks(let shown, let site):
            return [check, opened,
                    ChecklistStep(title: answerStep,
                                  notes: [String(localized: "\(shown) asks something before showing \(site) (cookies, signing in…). AutoHush goes on once it shows.",
                                                 comment: "Add a Web App window, under the step “Answer the site in Safari”; the first %@ is the site Safari shows instead (e.g. consent.youtube.com), the second the one typed (e.g. music.youtube.com)")],
                                  state: .current),
                    ChecklistStep(title: addStep, state: .todo), learnLater]
        case .readyToAdd(let site):
            return [check, opened] + answered
                + [ChecklistStep(title: addStep,
                                 notes: [String(localized: "Once \(site) shows in Safari (answer anything it asks first), click Add to Dock.",
                                                comment: "Add a Web App window, under the step “Add it to the Dock”, above the Add to Dock button; %@ is the website, e.g. music.youtube.com")],
                                 state: .current, button: .addToDock,
                                 warning: closedWithoutAdding
                                    ? String(localized: "Safari’s window was closed without adding it. Click Add to Dock to open it again.",
                                             comment: "Add a Web App window, under the step “Add it to the Dock”, after the user closed Safari's Add to Dock window with Cancel; “Add to Dock” is the button under it")
                                    : nil),
                   learnLater]
        case .adding:
            return [check, opened] + answered
                + [ChecklistStep(title: addStep,
                                 notes: [String(localized: "In Safari’s Add to Dock window, change the name if you like, then click Add.",
                                                comment: "Add a Web App window, under the step “Add it to the Dock”, while Safari's own Add to Dock window is open: the user may rename the web app there, then clicks its Add button")],
                                 state: .current),
                   learnLater]
        case .entering, .checking, .opening:
            return [check,
                    ChecklistStep(title: openStep, notes: phase == .opening ? [extensionTip] : [],
                                  state: phase == .opening ? .current : phase == .checking ? .todo : .done),
                    ChecklistStep(title: addStep, state: .todo), learnLater]
        }
    }

    /// While Safari opens the site: an extension's request for access
    /// holds it up until it's answered.
    private static var extensionTip: String {
        String(localized: "If a Safari extension asks for access to the site, answer it first.",
               comment: "Add a Web App window, under the step “Open it in Safari” while it's under way")
    }

    private static var openStep: String {
        String(localized: "Open it in Safari", comment: "Add a Web App window: a step")
    }

    /// Only when Safari shows another site first, asking something.
    private static var answerStep: String {
        String(localized: "Answer the site in Safari",
               comment: "Add a Web App window: a step shown only when the website asks something first on another of its sites (a cookie page, signing in)")
    }

    private static var addStep: String {
        String(localized: "Add it to the Dock", comment: "Add a Web App window: a step, before it's done")
    }

    /// The learning steps, before the web app is made.
    private static var learnStepTitle: String {
        String(localized: "Learn its controls", comment: "Add a Web App window: the last step, to come, until the web app is added: AutoHush then learns which of its buttons plays and pauses it (the learning steps replace this one)")
    }

    /// Learning, once the web app is made: the learning window's two steps
    /// (both ticked once learned).
    private static func learningSteps(_ name: String, learning: LearningStatus?, remaining: TimeInterval?,
                                      note: LearningNote?, pauseMode: LearningPauseMode, locked: Bool) -> [ChecklistStep] {
        guard case .learning(let hasPlayed)? = learning else {
            return LearningSteps.steps(name: name, hasPlayed: true, hasPaused: true, locked: false, pauseMode: pauseMode)
        }
        return LearningSteps.steps(name: name, hasPlayed: hasPlayed, hasPaused: false, locked: locked,
                                   remaining: remaining, note: note, pauseMode: pauseMode)
    }

    private func step(_ step: ChecklistStep, locked: Bool) -> some View {
        ChecklistStepRow(step: step, dimmed: step.state == .done || locked, bold: [.current, .failed].contains(step.state), action: { button in
            if button == .addToDock { model.addTapped() } else { settings.learningStep(button) }
        }) {
            StepSymbol(step: step, locked: locked, current: Image(systemName: "arrow.right.circle.fill"),
                       currentStyle: AnyShapeStyle(Color.accentColor))
        }
    }

    /// Safari's own icon (its app in /Applications is a link into the
    /// system), looked up once rather than at every redraw.
    private static let safariIcon: NSImage = {
        let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")?.resolvingSymlinksInPath().path
        return NSWorkspace.shared.icon(forFile: path ?? "/Applications/Safari.app")
    }()
}
