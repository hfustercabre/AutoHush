import AppKit
import AutoHushKit

/// Add a Web App… as a feature of its own: its model and window, making a
/// web app from an address, opening and choosing it, and a web app made but
/// not listed yet, picked up once it is. AppDelegate opens it; what it needs
/// from the rest of AutoHush it asks of its host (R16, the full check,
/// 2026-10-20), as Add an App does.
@MainActor
final class AddWebAppFeature {
    let model = AddWebAppModel()
    private(set) var window: (any AddWebAppPresenting)?
    /// The add under way, until it's done or cancelled.
    private(set) var adding: Task<Void, Never>?
    /// A web app made but not found as installed yet, and the address it was
    /// made from, while the window says so (`pickUpListed`).
    private(set) var awaitingListing: (bundleID: String, address: String)?

    private weak var host: (any AddWebAppHost)?
    /// Makes a Safari web app from an address.
    private let maker: any WebAppMaking
    private let makeWindow: @MainActor (AddWebAppModel, SettingsModel) -> any AddWebAppPresenting
    /// Opens an app (the web app just added, so it can be played).
    private let openApp: @MainActor (URL) async -> Void
    /// The learning shows both steps ticked this long before the window closes.
    private let learnedWindowDelay: Duration
    /// Between two looks for a web app just made that isn't listed yet.
    private let madeWebAppWait: Duration
    private let logger = AutoHushLogger(category: "AppDelegate")

    init(host: any AddWebAppHost, maker: any WebAppMaking,
         makeWindow: @escaping @MainActor (AddWebAppModel, SettingsModel) -> any AddWebAppPresenting,
         openApp: @escaping @MainActor (URL) async -> Void, learnedWindowDelay: Duration, madeWebAppWait: Duration,
         exampleAddress: String?, countrySites: [CountrySites]) {
        self.host = host
        self.maker = maker
        self.makeWindow = makeWindow
        self.openApp = openApp
        self.learnedWindowDelay = learnedWindowDelay
        self.madeWebAppWait = madeWebAppWait
        model.exampleAddress = exampleAddress
        model.countrySites = countrySites
        model.start = { [weak self] in self?.add(from: $0) }
        model.cancel = { [weak self] in self?.cancel() }
        model.openAccessibilitySettings = { [weak self] in self?.host?.requestSafariAccess() }
    }

    var isOpen: Bool { window?.isOpen == true }

    /// The "Add a Web App" window, ready for an address, filled in with
    /// `address` if there's one (or showing the one being added).
    func show(address: String? = nil) {
        if window == nil, let host { window = makeWindow(model, host.settingsForWindows) }
        if adding == nil, address != nil || window?.isOpen != true {
            model.reset(address: address ?? "")
        }
        window?.show()
        host?.followWindows() // follows Accessibility, which adding needs
    }

    /// Closes the window, an add under way with it (cancelled, as its
    /// Cancel does).
    func close() {
        if let window, window.isOpen { window.close() }
    }

    /// Makes the address a web app, then opens it, chooses it, and lets the
    /// window show the learning (or, added while the welcome window shows,
    /// closes: the welcome window goes on). Closing the window cancels it
    /// until the web app is made.
    func add(from address: String) {
        guard adding == nil else { return }
        awaitingListing = nil
        let model = model
        let maker = maker
        model.attempt += 1
        let attempt = model.attempt
        // Another player chosen while it's added (the user's, from the menu) stays.
        let before = host?.chosenPlayerID
        adding = Task { [weak self] in
            defer { if model.attempt == attempt { self?.adding = nil } }
            do {
                let made = try await maker.makeWebApp(from: address, onStep: { step in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard model.attempt == attempt else { return } // cancelled since
                            model.apply(step)
                        }
                    }
                }, confirmAdd: {
                    // The user clicks Add to Dock once the site shows.
                    await model.waitForAdd(attempt: attempt)
                })
                guard let self, let host = self.host, model.attempt == attempt, !Task.isCancelled else { return }
                model.apply(.made(made))
                self.logger.notice("Web app ready: \(made.name, privacy: .public)\(made.alreadyThere ? " (already there)" : "", privacy: .public)")
                // Opened first, so it's running by the time it's chosen.
                await self.openApp(made.url)
                // Added while the welcome window shows (from it, or from the
                // menu meanwhile): that one asks for what the web app needs,
                // and the learning window follows its Done, as for a web app
                // picked there; this window's work is done.
                let fromWelcome = host.isShowingPlayerChooser
                // Another player chosen meanwhile (the user's) stays: the web
                // app is added, and this window has nothing left to show (the
                // workflow audit, 2026-10-22).
                guard host.chosenPlayerID == before else {
                    self.window?.close()
                    return
                }
                host.chooseWebApp(made.bundleID, showsLearningWindow: fromWelcome)
                // macOS may list a new web app a little later: looked for again
                // for a few seconds, then the window says so.
                var lookups = 0
                while host.chosenPlayerID == before, before != made.bundleID, lookups < Self.madeWebAppLookups,
                      model.attempt == attempt, !Task.isCancelled {
                    lookups += 1
                    try? await Task.sleep(for: self.madeWebAppWait)
                    guard host.chosenPlayerID == before else { break }
                    host.chooseWebApp(made.bundleID, showsLearningWindow: fromWelcome)
                }
                guard model.attempt == attempt, !Task.isCancelled else { return }
                guard host.chosenPlayerID == made.bundleID else {
                    guard host.chosenPlayerID == before else { // the user chose another one
                        self.window?.close()
                        return
                    }
                    self.logger.error("\(made.name, privacy: .public) was made but can’t be chosen: it isn’t found as installed")
                    model.fail(.notFound(name: made.name))
                    // Picked up by itself once it's listed (`pickUpListed`).
                    self.awaitingListing = (made.bundleID, address)
                    host.followWindows()
                    return
                }
                if fromWelcome {
                    self.window?.close()
                    return
                }
                // Chosen and learned already: there's nothing left to show.
                if host.chosenPlayerIsLearned {
                    try? await Task.sleep(for: self.learnedWindowDelay)
                    if case .learning = model.phase { self.window?.close() }
                }
            } catch is CancellationError {
                // Logged when it was cancelled.
            } catch {
                guard model.attempt == attempt else { return }
                let failure = error as? WebAppMakingError ?? .browserFailed(error.localizedDescription)
                self?.logger.error("Couldn’t add a web app: \(failure.kind, privacy: .public) (\(String(describing: failure), privacy: .private))")
                model.fail(failure)
            }
        }
    }

    /// How many times a web app just made is looked for again, `madeWebAppWait`
    /// apart, before the window says it can't be found.
    static let madeWebAppLookups = 10

    /// The web app made but not found as installed, while the window says
    /// so: once it's listed (the window watch checks the players each second
    /// meanwhile), it's added again as it stands, which chooses it, without
    /// waiting for Continue. Not once the address was changed.
    func pickUpListed(among options: [PlayerOption]) {
        guard let awaiting = awaitingListing else { return }
        guard case .notFound? = model.problem, model.phase == .entering, model.address == awaiting.address, isOpen else {
            awaitingListing = nil
            return
        }
        guard host?.isPlayer(awaiting.bundleID) == true,
              options.contains(where: { $0.bundleID == awaiting.bundleID && $0.isInstalled }) else { return }
        awaitingListing = nil
        logger.notice("The web app made is listed now: adding it again")
        model.continueTapped()
    }

    /// Stops the add under way; a step it reports later is ignored.
    func cancel() {
        guard let task = adding else { return }
        logger.notice("Adding a web app was cancelled")
        task.cancel()
        adding = nil
        model.attempt += 1
    }
}

private extension WebAppMakingError {
    /// What went wrong, without the address, for the log: what the user
    /// typed stays private there.
    var kind: String {
        switch self {
        case .notAWebAddress: "not a web address"
        case .noAnswer: "the site didn't answer"
        case .pageNotFound: "the page doesn't exist"
        case .accessibilityDenied: "no Accessibility permission"
        case .browserFailed: "Safari didn't do it"
        case .notFound: "the web app isn't found as installed"
        }
    }
}
