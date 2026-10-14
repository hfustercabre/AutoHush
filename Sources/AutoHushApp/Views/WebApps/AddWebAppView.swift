import AppKit
import SwiftUI
import AutoHushKit

// "Add a Web App…", in the menu's players, Settings → General and the
// welcome window (the last tile, "Add…"): the user pastes a
// website's address, AutoHush opens it in Safari and, once the site shows
// and the user clicks Add to Dock, makes it a Safari web app (Safari's own
// Add to Dock), chooses it, opens it and learns its controls, ticking each
// step in one window.

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
                WindowHeader(icon: AppIcon.safari,
                             description: Text("Paste the address of a website that plays music, podcasts or videos. AutoHush opens it in Safari, adds it to your Dock as an app, and learns its controls.",
                                               comment: "Add a Web App window, at its top beside Safari's icon"))
                NoteLabel(PlayerOption.webAppsWarning)
                    .padding(.top, 8)
                // Adding drives Safari through Accessibility: without it, the
                // window says so first, and Continue waits until it's allowed.
                if needsAccessibility {
                    VStack(alignment: .leading, spacing: 8) {
                        NoteLabel(Self.accessibilityNeeded)
                        PermissionButton(model: settings, permission: Self.safariAccess, access: .denied, long: true)
                    }
                }
                SectionHeading(Text("Address", comment: "Add a Web App window: the heading over the field for the website's address"))
                    .padding(.top, 8)
                if let sites = model.addressSites {
                    Card {
                        addressField
                        CardDivider()
                        countryRow(sites)
                    }
                    if model.phase == .entering {
                        Text("\(sites.name) has its own site in some countries, and you can sign in only on your account’s.",
                             comment: "Add a Web App window, under the address and the country row of a service with its own site in some countries; %@ is the service, e.g. Amazon Music")
                            .captionStyle()
                    }
                } else {
                    Card { addressField }
                }
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
        // VoiceOver hears why the last try failed, as it shows under the field.
        .onChange(of: model.problemText) { _, problem in
            if let problem { AccessibilityNotification.Announcement(problem).post() }
        }
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

    /// Why adding waits, over the address; VoiceOver announces it too.
    private static var accessibilityNeeded: String {
        String(localized: "AutoHush needs Accessibility access to add it with Safari. Continue unlocks once it’s allowed.",
               comment: "Add a Web App window, while the Accessibility permission is missing")
    }

    private var addressField: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .foregroundStyle(.appSecondary)
                .accessibilityHidden(true)
            TextField(text: Binding(get: { model.address }, set: { model.address = $0 })) {
                Text(verbatim: model.exampleAddress ?? "")
            }
            .textFieldStyle(.plain)
            .accessibilityLabel(Text("Address", comment: "Add a Web App window: the heading over the field for the website's address"))
            .disabled(model.phase != .entering)
            .onSubmit { if !needsAccessibility { model.continueTapped() } } // Return, as Continue
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(.chipFill))
    }

    /// The countries of `sites`, each opening its site: the Mac's region
    /// chosen at first, and "Other Countries" for the rest of the world.
    private func countryRow(_ sites: CountrySites) -> some View {
        HStack(spacing: 10) {
            Self.countryLabel
                .accessibilityHidden(true) // the pop-up says it, as its label
            Spacer(minLength: 8)
            Picker(selection: Binding(get: { model.country(in: sites) }, set: { model.chooseCountry($0, in: sites) })) {
                ForEach(model.countries(of: sites), id: \.code) { Text(verbatim: $0.name).tag($0.code) }
                Divider()
                Text("Other Countries", comment: "Add a Web App window, last in the pop-up of countries under the address of a service with its own site in some countries (Amazon Music): every country without a site of its own")
                    .tag("")
            } label: {
                Self.countryLabel
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .buttonStyle(.borderless)
            .fixedSize()
            .disabled(model.phase != .entering)
        }
    }

    private static var countryLabel: Text {
        Text("Your account’s country", comment: "Add a Web App window: the row under the address of a service with its own site in some countries (Amazon Music), before the pop-up of countries; the site changes with the country")
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
        let groups = Self.stepGroups(for: model.phase, siteAsked: model.siteAsked, closedWithoutAdding: model.closedWithoutAdding,
                                     learning: settings.learning,
                                     remaining: remaining, note: settings.learningNote, pauseMode: settings.learningPauseMode,
                                     locked: locked)
        let steps = groups.adding + groups.learning
        // Locked, the permission comes right above the learning steps it
        // unlocks.
        let before = locked ? groups.adding : steps
        let after = locked ? groups.learning : []
        // Waiting for a permission, VoiceOver hears why instead of a step.
        var announcement = steps.currentAnnouncement
        if locked, let control = settings.permissions.control, case .learning(let name, _) = model.phase {
            announcement = LearningPermissionStep.announcement(control, name: name)
        } else if needsAccessibility {
            announcement = Self.accessibilityNeeded
        }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(before, id: \.title) { step($0, locked: false) }
            if locked, let control = settings.permissions.control, case .learning(let name, _) = model.phase {
                LearningPermissionStep(model: settings, permission: control, access: settings.permissions.controlAccess, name: name)
                ForEach(after, id: \.title) { step($0, locked: true) }
            }
        }
        .announcesCurrentStep(announcement, atOnce: locked || needsAccessibility)
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
        let groups = stepGroups(for: phase, siteAsked: siteAsked, closedWithoutAdding: closedWithoutAdding, learning: learning,
                                remaining: remaining, note: note, pauseMode: pauseMode, locked: locked)
        return groups.adding + groups.learning
    }

    /// `steps(for:…)` in two: adding the web app, then learning it, once
    /// it's made (none before): a missing permission locks the learning
    /// ones, however many there are (pausing it by hand adds one).
    static func stepGroups(for phase: AddWebAppModel.Phase, siteAsked: Bool = false, closedWithoutAdding: Bool = false,
                           learning: LearningStatus?,
                           remaining: TimeInterval? = nil, note: LearningNote? = nil,
                           pauseMode: LearningPauseMode = .automatic, locked: Bool = false)
        -> (adding: [ChecklistStep], learning: [ChecklistStep]) {
        let check = ChecklistStep(title: String(localized: "Check the address", comment: "Add a Web App window: a step"),
                                  state: phase == .checking ? .current : .done)
        let opened = ChecklistStep(title: openStep, state: .done)
        let answered = siteAsked ? [ChecklistStep(title: answerStep, state: .done)] : []
        let learnLater = ChecklistStep(title: learnStepTitle, state: .todo)
        switch phase {
        case .learning(let name, true):
            return ([check,
                     ChecklistStep(title: String(localized: "Already in your Dock as “\(name)”",
                                                 comment: "Add a Web App window: a step, when the website already has a web app; %@ is its name"),
                                   state: .done)],
                    learningSteps(name, learning: learning, remaining: remaining, note: note, pauseMode: pauseMode, locked: locked))
        case .learning(let name, false):
            return ([check, opened] + answered
                        + [ChecklistStep(title: String(localized: "Add it to the Dock as “\(name)”",
                                                       comment: "Add a Web App window: a step done; %@ is the web app's name"),
                                         state: .done)],
                    learningSteps(name, learning: learning, remaining: remaining, note: note, pauseMode: pauseMode, locked: locked))
        case .siteAsks(let shown, let site):
            return ([check, opened,
                    ChecklistStep(title: answerStep,
                                  notes: [String(localized: "\(shown) asks something before showing \(site) (cookies, signing in…). AutoHush goes on once it shows.",
                                                 comment: "Add a Web App window, under the step “Answer the site in Safari”; the first %@ is the site Safari shows instead (e.g. consent.youtube.com), the second the one typed (e.g. music.youtube.com)")],
                                  state: .current),
                    ChecklistStep(title: addStep, state: .todo), learnLater], [])
        case .readyToAdd(let site):
            return ([check, opened] + answered
                + [ChecklistStep(title: addStep,
                                 notes: [String(localized: "Once \(site) shows in Safari (answer anything it asks first), click Add to Dock.",
                                                comment: "Add a Web App window, under the step “Add it to the Dock”, above the Add to Dock button; %@ is the website, e.g. music.youtube.com")],
                                 state: .current, button: .addToDock,
                                 warning: closedWithoutAdding
                                    ? String(localized: "Safari’s window was closed without adding it. Click Add to Dock to open it again.",
                                             comment: "Add a Web App window, under the step “Add it to the Dock”, after the user closed Safari's Add to Dock window with Cancel; “Add to Dock” is the button under it")
                                    : nil),
                   learnLater], [])
        case .adding:
            return ([check, opened] + answered
                + [ChecklistStep(title: addStep,
                                 notes: [String(localized: "In Safari’s Add to Dock window, change the name if you like, then click Add.",
                                                comment: "Add a Web App window, under the step “Add it to the Dock”, while Safari's own Add to Dock window is open: the user may rename the web app there, then clicks its Add button")],
                                 state: .current),
                   learnLater], [])
        case .entering, .checking, .opening:
            return ([check,
                     ChecklistStep(title: openStep, notes: phase == .opening ? [extensionTip] : [],
                                   state: phase == .opening ? .current : phase == .checking ? .todo : .done),
                     ChecklistStep(title: addStep, state: .todo), learnLater], [])
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
            if button == .addToDock { model.addTapped() } else { settings.learningSession.step(button) }
        }) {
            StepSymbol(step: step, locked: locked)
        }
    }
}
