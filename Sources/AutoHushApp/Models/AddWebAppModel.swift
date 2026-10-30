import Foundation
import Observation
import AutoHushKit

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
    /// The services with their own site in some countries (the player
    /// catalog's): for one of their sites, the window offers the others by
    /// country.
    var countrySites: [CountrySites] = []
    /// The Mac's region, the country chosen until another is.
    var region: String? = Locale.current.region?.identifier
    /// The country picked for the address, while it's that country's site.
    private(set) var pickedCountry: String?
    /// Each service's countries by name, worked out once (`countries(of:)`).
    @ObservationIgnored private var countryLists: [String: [Country]] = [:]

    /// A country with a site of its own, by region code, named in the Mac's
    /// language.
    struct Country: Hashable {
        let code: String
        let name: String
    }
    private(set) var phase = Phase.entering
    /// Why the last try failed; shown under the field.
    private(set) var problem: WebAppMakingError?
    /// The site asked something first, on this try: the step that said so
    /// stays, ticked.
    private(set) var siteAsked = false
    /// Safari's Add to Dock dialog was closed without adding: the Add to
    /// Dock step says so, until it's opened again.
    private(set) var closedWithoutAdding = false
    /// The web app the last try made (or found already there), once it has.
    private(set) var madeBundleID: String?
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
    /// What adding a web app needs: Accessibility, to drive Safari.
    static let safariAccess = Permission.accessibility(player: "Safari")

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

    /// The sites of the service whose site the address is, to choose one by
    /// country; `nil` for any other address.
    var addressSites: CountrySites? {
        countrySites.first { $0.covers(address: address) }
    }

    /// The country whose site the address is, as `sites` lists it ("" for
    /// every other country): the one picked, else the Mac's region.
    func country(in sites: CountrySites) -> String {
        sites.country(of: address, preferring: [pickedCountry, region].compactMap { $0 })
    }

    /// The countries with a site of their own, by name in the Mac's language.
    func countries(of sites: CountrySites) -> [Country] {
        if let list = countryLists[sites.name] { return list }
        let list = sites.byRegion.keys
            .map { Country(code: $0, name: Locale.current.localizedString(forRegionCode: $0) ?? $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        countryLists[sites.name] = list
        return list
    }

    /// Puts `country`'s site (`sites` lists it; "" for every other country)
    /// in the address.
    func chooseCountry(_ country: String, in sites: CountrySites) {
        guard phase == .entering else { return }
        pickedCountry = country
        address = sites.site(region: country)
    }

    /// Ready for an address: `address`, or none.
    func reset(address: String = "") {
        self.address = address
        pickedCountry = nil
        phase = .entering
        problem = nil
        siteAsked = false
        closedWithoutAdding = false
        madeBundleID = nil
        resumeAdd(false)
    }

    func continueTapped() {
        guard canContinue else { return }
        problem = nil
        siteAsked = false
        closedWithoutAdding = false
        madeBundleID = nil
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
            madeBundleID = app.bundleID
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
                String(localized: "That isn’t a web address. Try one like \(example).",
                       comment: "Add a Web App window, under the address field; %@ is a music website's address, e.g. music.youtube.com")
            } else {
                String(localized: "That isn’t a web address.", comment: "Add a Web App window, under the address field")
            }
        case .noAnswer(let host)?:
            String(localized: "\(host) doesn’t answer. Check the address and your connection.",
                   comment: "Add a Web App window; %@ is the website, e.g. music.youtube.com")
        case .pageNotFound(let host)?:
            String(localized: "\(host) says this page doesn’t exist. Check the address.",
                   comment: "Add a Web App window; %@ is the website, e.g. music.youtube.com")
        case .accessibilityDenied?:
            String(localized: "AutoHush needs Accessibility access to add it with Safari.",
                   comment: "Add a Web App window, when the Accessibility permission is missing")
        case .browserFailed?:
            String(localized: "Safari didn’t add it. Try again.", comment: "Add a Web App window, when Safari didn't make the web app")
        case .notFound(let name)?:
            String(localized: "\(name) was added, but AutoHush can’t find it yet. Click Continue to try again.",
                   comment: "Add a Web App window, when the web app was made but macOS doesn't list it yet; %@ is the web app's name; Continue is the window's button")
        case nil:
            nil
        }
    }
}
