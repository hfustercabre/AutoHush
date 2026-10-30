import AppKit
import SwiftUI
import AutoHushKit

// "Add a Web App…", in the menu's players, Settings → Media Player and the
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
    /// The step VoiceOver's cursor goes to as the checklist moves on: it reads
    /// the step then, and again on coming back to the window. An
    /// announcement alone went unheard after Continue, VoiceOver reading the
    /// dimmed field or the web app's window instead (2026-10-18/19).
    @AccessibilityFocusState private var focusedStep: String?
    /// Whether the window is key: back in front, the cursor goes to the step
    /// again (`stepList`). (`appearsActive` replaces it from macOS 15.)
    @Environment(\.controlActiveState) private var activeState
    /// The step to do now, for that move a second later: `focusedStep`
    /// follows VoiceOver's cursor, wherever VoiceOver puts it.
    @State private var currentStep: String?
    /// That move, waiting for its second: one coming back in front again
    /// replaces it, so they don't pile up.
    @State private var refocus: Task<Void, Never>?

    /// The window's width, which its bottom bar's buttons fit in every language.
    static let width: CGFloat = 440

    var body: some View {
        WindowPage(icon: AppIcon.safari,
                   description: Text("Paste a website that plays music, podcasts or videos. AutoHush adds it to your Dock as an app and learns its controls.",
                                     comment: "Add a Web App window, at its top beside Safari's icon"),
                   width: Self.width) {
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
            SectionHeading(Self.addressTitle)
                .padding(.top, 8)
            if let sites = model.addressSites {
                Card {
                    addressField
                    CardDivider()
                    countryRow(sites)
                }
                if model.phase == .entering {
                    Text("\(sites.name) has its own site in some countries, and you can sign in only on your account’s.",
                         comment: "Add a Web App window, under the address and the country row of a service with its own site in some countries; %@ is the service, e.g. Jukebox")
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
        } bar: {
            Spacer()
            Button { close() } label: {
                if case .learning = model.phase {
                    // The web app is added: its controls can be learned
                    // later, from the menu's or Settings' Controls row.
                    Text(verbatim: LaterText.title)
                } else {
                    Text(verbatim: ButtonText.cancel)
                }
            }
            .buttonStyle(.chip)
            .keyboardShortcut(.cancelAction)
            if model.phase == .entering {
                MainButton(ButtonText.continue) { model.continueTapped() }
                    .disabled(!model.canContinue || needsAccessibility)
            }
        }
        // VoiceOver hears why the last try failed, as it shows under the field.
        .onChange(of: model.problemText) { _, problem in
            if let problem { AccessibilityNotification.Announcement(problem).post() }
        }
        // And why Continue waits, as the window opens and when it starts to.
        .announcesCurrentStep(needsAccessibility ? Self.accessibilityNeeded : nil, atOnce: true)
    }

    /// Over the card of steps, here and in the learning window.
    static var stepsHeading: Text {
        Text("Steps", comment: "Add a Web App and learning windows: the heading over the steps of adding a web app and learning its controls")
    }

    /// Accessibility, which adding needs, is missing while an address is typed.
    private var needsAccessibility: Bool {
        model.phase == .entering && !settings.permissions.accessibility
    }

    private static let safariAccess = AddWebAppModel.safariAccess

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
            .accessibilityLabel(Self.addressTitle)
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
                Text("Other Countries", comment: "Add a Web App window, last in the pop-up of countries under the address of a service with its own site in some countries: every country without a site of its own")
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

    /// Over the address's card, and its field's name for VoiceOver.
    private static var addressTitle: Text {
        Text("Address", comment: "Add a Web App window: the heading over the field for the website's address")
    }

    private static var countryLabel: Text {
        Text("Your account’s country", comment: "Add a Web App window: the row under the address of a service with its own site in some countries, before the pop-up of countries; the site changes with the country")
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
                                     madeIsChosen: model.madeBundleID == settings.chosenPlayerID,
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
        }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(before, id: \.title) { step($0, locked: false) }
            if locked, let control = settings.permissions.control, case .learning(let name, _) = model.phase {
                LearningPermissionStep(model: settings, permission: control, access: settings.permissions.controlAccess, name: name)
                ForEach(after, id: \.title) { step($0, locked: true) }
            }
        }
        .announcesCurrentStep(announcement, atOnce: locked)
        .onChange(of: steps.currentTitle, initial: true) { old, title in
            currentStep = title
            if let title, title != old { focusedStep = title }
        }
        // Back in front (after Safari's window or the web app's), VoiceOver
        // reads where its cursor is, and a move made while another app was in
        // front never reached it: it read a step done before (heard in the VM,
        // 2026-10-21). So the cursor moves to the step again, a second later:
        // VoiceOver puts it back where it was as the window comes in front.
        .onChange(of: activeState) { _, state in
            guard state == .key, currentStep != nil else { return }
            refocus?.cancel()
            refocus = Task {
                guard (try? await Task.sleep(for: .seconds(1))) != nil else { return } // replaced meanwhile
                focusedStep = nil
                try? await Task.sleep(for: .milliseconds(50))
                focusedStep = currentStep // the newest, should one have come meanwhile
            }
        }
    }

    /// Once the web app is chosen, learning it needs its control permission
    /// (Accessibility): without it, the learning steps wait, locked.
    private var learningLocked: Bool {
        guard case .learning = model.phase else { return false }
        return settings.permissions.controlMissing(for: settings.chosenPlayerID)
    }

    private func step(_ step: ChecklistStep, locked: Bool) -> some View {
        ChecklistStepRow(step: step, dimmed: step.state == .done || locked, bold: [.current, .failed].contains(step.state),
                         focus: $focusedStep, action: { button in
            if button == .addToDock { model.addTapped() } else { settings.learningSession.step(button) }
        }) {
            StepSymbol(step: step, locked: locked)
        }
    }
}
