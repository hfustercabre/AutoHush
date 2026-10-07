import AppKit
import SwiftUI
import AutoHushKit

// "Add a Web App…", in the menu's players, Settings → General (its "+" and
// the pop-up's last item) and the welcome window: the user pastes a
// website's address, and AutoHush makes it a Safari web app (Safari's own
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
        case adding
        /// The web app is the player; AutoHush learns it (or already knows it).
        case learning(name: String, alreadyThere: Bool)
    }

    var address = ""
    private(set) var phase = Phase.entering
    /// Why the last try failed; shown under the field.
    private(set) var problem: WebAppMakingError?

    @ObservationIgnored var start: @MainActor (String) -> Void = { _ in }
    /// Stops the add under way.
    @ObservationIgnored var cancel: @MainActor () -> Void = {}
    /// Counts the adds started, so steps a cancelled one reports later are
    /// told apart.
    @ObservationIgnored var attempt = 0
    @ObservationIgnored var openAccessibilitySettings: @MainActor () -> Void = {}

    /// The address is being checked, opened or added in Safari.
    var isAdding: Bool { [.checking, .opening, .adding].contains(phase) }

    /// Whether what's typed can be tried: something that could be an address.
    var canContinue: Bool {
        phase == .entering && !address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Ready for an address: `address`, or none.
    func reset(address: String = "") {
        self.address = address
        phase = .entering
        problem = nil
    }

    func continueTapped() {
        guard canContinue else { return }
        problem = nil
        phase = .checking
        start(address)
    }

    /// The window closed: an add under way stops (Safari's dialog is
    /// cancelled, nothing is added). Once the web app is made, learning goes
    /// on in the menu and Settings.
    func windowClosed() {
        guard isAdding else { return }
        cancel()
        reset()
    }

    func apply(_ step: WebAppMakingStep) {
        guard phase != .entering else { return } // a step reported after it was cancelled
        switch step {
        case .checked:          phase = .opening
        case .opened:           phase = .adding
        case .made(let app):    phase = .learning(name: app.name, alreadyThere: app.alreadyThere)
        }
    }

    func fail(_ error: WebAppMakingError) {
        problem = error
        phase = .entering
    }

    /// The problem in words.
    var problemText: String? {
        switch problem {
        case .notAWebAddress?:
            String(localized: "That isn't a web address. Try one like music.youtube.com.",
                   comment: "Add a Web App window, under the address field")
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
                   title: String(localized: "Add a Web App", comment: "Title and heading of the window that makes a website a Safari web app"))
        window?.delegate = self
        hosting.rootView = AddWebAppView(model: model, settings: settings) { [weak self] in self?.close() }
    }

    /// Closing it (Cancel, Later or its close button) stops an add under way.
    func windowWillClose(_ notification: Notification) {
        model.windowClosed()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// The window's content: what it's for, the address, then each step.
struct AddWebAppView: View {
    let model: AddWebAppModel
    /// For the learning that follows (the chosen player's status).
    let settings: SettingsModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: Self.safariIcon)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a Web App", comment: "Title and heading of the window that makes a website a Safari web app")
                        .font(.appTitle)
                    Text("Paste the address of a music website. AutoHush opens it in Safari, adds it to your Dock as an app, and learns its controls.",
                         comment: "Add a Web App window, under its heading")
                        .captionStyle()
                }
            }
            NoteLabel(PlayerOption.webAppsWarning)
            // Adding drives Safari through Accessibility: without it, the
            // window says so first, and Continue waits until it's allowed.
            if needsAccessibility {
                VStack(alignment: .leading, spacing: 8) {
                    NoteLabel(String(localized: "AutoHush needs Accessibility access to add it with Safari. Continue unlocks once it’s allowed.",
                                     comment: "Add a Web App window, while the Accessibility permission is missing"))
                    PermissionButton(model: settings, permission: Self.safariAccess, access: .denied, long: true)
                }
            }
            addressField
            if let problem = model.problemText, !(needsAccessibility && model.problem == .accessibilityDenied) {
                NoteLabel(problem)
                if model.problem == .accessibilityDenied {
                    Button(Self.safariAccess.grantTitle) { model.openAccessibilitySettings() }
                        .buttonStyle(.chip)
                }
            }
            if model.phase != .entering { Card { steps } }
            HStack(spacing: 8) {
                Spacer()
                Button { close() } label: {
                    if case .learning = model.phase {
                        // The web app is added: learning goes on in the menu.
                        Text("Later", comment: "Button that closes it for now: an update alert, or a window that learns a web app's controls (the learning window, the Add a Web App window)")
                    } else {
                        Text("Cancel", comment: "Add a Web App window: stops adding the website and closes the window")
                    }
                }
                .buttonStyle(.chip)
                if model.phase == .entering {
                    Button { model.continueTapped() } label: {
                        Text("Continue", comment: "Button in the welcome window and the Add a Web App window: goes on with what's chosen or typed").font(.appBody.weight(.semibold)).padding(.horizontal, 6)
                    }
                    // Blue, without Return: AutoHush has no keyboard shortcuts.
                    .buttonStyle(ChipButtonStyle(filled: true, isSelected: true, padded: true))
                    .disabled(!model.canContinue || needsAccessibility)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .font(.appBody)
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
                Text(verbatim: "music.youtube.com")
            }
            .textFieldStyle(.plain)
            .disabled(model.phase != .entering)
            .onSubmit {} // no Return shortcut: Continue is clicked
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(.chipFill))
    }

    // MARK: - The steps

    private enum StepState { case done, current, todo }

    @ViewBuilder private var steps: some View {
        VStack(alignment: .leading, spacing: 8) {
            step(model.phase == .checking ? .current : .done,
                 String(localized: "Check the address", comment: "Add a Web App window: a step"))
            switch model.phase {
            case .learning(let name, true):
                step(.done, String(localized: "Already in your Dock as “\(name)”",
                                   comment: "Add a Web App window: a step, when the website already has a web app; %@ is its name"))
                learningStep(name)
            case .learning(let name, false):
                step(.done, openStep)
                step(.done, String(localized: "Add it to the Dock as “\(name)”",
                                   comment: "Add a Web App window: a step done; %@ is the web app's name"))
                learningStep(name)
            default:
                step(model.phase == .opening ? .current : model.phase == .checking ? .todo : .done, openStep,
                     notes: model.phase == .opening ? [extensionTip] : [])
                step(model.phase == .adding ? .current : .todo,
                     String(localized: "Add it to the Dock", comment: "Add a Web App window: a step, before it's done"))
                step(.todo, learnStepTitle)
            }
        }
    }

    /// While Safari opens the site: an extension's request for access
    /// holds it up until it's answered.
    private var extensionTip: String {
        String(localized: "If a Safari extension asks for access to the site, answer it first.",
               comment: "Add a Web App window, under the step “Open it in Safari” while it's under way")
    }

    private var openStep: String {
        String(localized: "Open it in Safari", comment: "Add a Web App window: a step")
    }

    private var learnStepTitle: String {
        String(localized: "Play something in it, then pause it", comment: "Add a Web App window: the last step")
    }

    @ViewBuilder private func learningStep(_ name: String) -> some View {
        switch settings.learning {
        case .learning(let hasPlayed)?:
            step(.current, learnStepTitle, notes: hasPlayed
                 ? [String(localized: "Now pause it.", comment: "Add a Web App window, once the web app has played"),
                    LearningText.pauseTip]
                 : [String(localized: "\(name) is open. AutoHush watches which button plays and pauses it.",
                           comment: "Add a Web App window, under its last step; %@ is the web app"),
                    LearningText.playTip(name)])
        default:
            step(.done, learnStepTitle)
        }
    }

    private func step(_ state: StepState, _ text: String, notes: [String] = []) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                switch state {
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.appSuccess)
                case .current: Image(systemName: "arrow.right.circle.fill").foregroundStyle(Color.accentColor)
                case .todo: Image(systemName: "circle").foregroundStyle(.appSecondary)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: text)
                    .foregroundStyle(state == .done ? AnyShapeStyle(.appSecondary) : AnyShapeStyle(.primary))
                    .fontWeight(state == .current ? .semibold : .regular)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(notes, id: \.self) { Text(verbatim: $0).captionStyle().fixedSize(horizontal: false, vertical: true) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(state == .done ? .isSelected : [])
    }

    /// Safari's own icon (its app in /Applications is a link into the
    /// system), looked up once rather than at every redraw.
    private static let safariIcon: NSImage = {
        let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")?.resolvingSymlinksInPath().path
        return NSWorkspace.shared.icon(forFile: path ?? "/Applications/Safari.app")
    }()
}

extension PlayerOption {
    /// Where players are offered: the entry that adds a Safari web app.
    static var addWebAppTitle: String {
        String(localized: "Add a Web App…",
               comment: "Menu item and button where music players are offered: makes a website a Safari web app")
    }
}
