import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport

/// Settings → Sound Sources' list: its rows, order, search, selection and
/// removals (moved from SettingsModelTests with the model, X20, the full
/// check, 2026-10-19).
@Suite("AppListModel")
@MainActor
struct AppListModelTests {
    /// The app's state, which the list reads the apps from.
    private let state = AppState()

    /// The list, reading `state`, ordered and removed from in `settings`.
    private func makeList(settings: UserSettings = .inMemory()) -> AppListModel {
        AppListModel(state: state, settings: settings)
    }

    /// The user's settings, with these apps seen and ignored.
    private func userSettings(seen: [AudioSource], ignored: [AudioSource] = []) -> UserSettings {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        preferences.recordSeen(seen)
        preferences.ignoredApps = ignored
        return UserSettings(preferences: preferences)
    }

    /// The apps as the app's state has them.
    private func show(seen: [AudioSource], ignored: [AudioSource]) {
        state.status.seenApps = seen
        state.status.ignoredApps = ignored
    }

    /// Five apps, listed in this order (Last Played, the most recent first).
    private static let listed = ["Arc", "Books", "Chess", "Discord", "Edge"].map {
        AudioSource(id: "com.example.\($0.lowercased())", name: $0)
    }
    private static let ids = listed.map(\.id)

    /// The model listing `listed`, `ignored` turned off, and the user's settings it removes them from.
    private func listing(ignored: [AudioSource] = []) -> (model: AppListModel, settings: UserSettings) {
        let settings = userSettings(seen: Self.listed, ignored: ignored)
        let model = makeList(settings: settings)
        show(seen: Self.listed, ignored: ignored)
        return (model, settings)
    }

    /// The selected apps' IDs, in the list's order.
    private func selected(_ model: AppListModel) -> [String] { model.selectedApps.map(\.id) }

    @Test("the apps list merges seen and ignored apps, the most recent first, then those that never played")
    func appsList() {
        let model = makeList()
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        let zoom = AudioSource(id: "us.zoom.xos", name: "zoom.us")
        show(seen: [vlc, chrome], ignored: [AudioSource(id: vlc.id, name: "VLC"), zoom])

        #expect(model.apps.map(\.source.name) == ["VLC", "Google Chrome", "zoom.us"])
        #expect(model.apps.map(\.isIgnored) == [true, false, true])
        #expect(model.apps.map(\.playedRank) == [0, 1, nil])
        #expect(model.apps[0].source.bundlePath == "/Applications/VLC.app") // the seen entry keeps its icon
    }

    @Test("the apps can be ordered by last played, name or on/off, each either way round")
    func appsOrder() {
        let model = makeList()
        let safari = AudioSource(id: "com.apple.Safari", name: "Safari")
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        let zoom = AudioSource(id: "us.zoom.xos", name: "zoom.us")
        let arc = AudioSource(id: "company.thebrowser.Browser", name: "Arc")
        // Played most recently: Safari, VLC, Chrome, Arc; zoom was ignored without playing.
        show(seen: [safari, vlc, chrome, arc], ignored: [vlc, zoom])
        /// What Sort by says of the way round, then the apps in that order.
        func names(_ criterion: AppListOrder.Criterion, reversed: Bool = false) -> [String] {
            model.setOrder(AppListOrder(criterion: criterion, isReversed: reversed))
            return [model.order.directionTitle] + model.apps.map(\.source.name)
        }

        #expect(names(.lastPlayed) == ["Newest first", "Safari", "VLC", "Google Chrome", "Arc", "zoom.us"])
        #expect(names(.lastPlayed, reversed: true) == ["Oldest first", "zoom.us", "Arc", "Google Chrome", "VLC", "Safari"])
        #expect(names(.name) == ["A to Z", "Arc", "Google Chrome", "Safari", "VLC", "zoom.us"])
        #expect(names(.name, reversed: true) == ["Z to A", "zoom.us", "VLC", "Safari", "Google Chrome", "Arc"])
        // Each group stays A to Z; reversed, only the groups swap.
        #expect(names(.state) == ["Apps that pause playback first", "Arc", "Google Chrome", "Safari", "VLC", "zoom.us"])
        #expect(names(.state, reversed: true) == ["Ignored apps first", "VLC", "zoom.us", "Arc", "Google Chrome", "Safari"])

        // New apps arrive in the chosen order.
        model.setOrder(AppListOrder(criterion: .name, isReversed: true))
        show(seen: [chrome, safari], ignored: [])
        #expect(model.apps.map(\.source.name) == ["Safari", "Google Chrome"])
    }

    @Test("the search narrows the apps to the names that match, ignoring case and accents, in the chosen order")
    func appSearch() {
        let model = makeList()
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        let facetime = AudioSource(id: "com.apple.FaceTime", name: "FaceTime")
        let musica = AudioSource(id: "com.example.musica", name: "Música")
        let safari = AudioSource(id: "com.apple.Safari", name: "Safari")
        show(seen: [facetime, safari, chrome, musica], ignored: [])
        #expect(model.shownApps == model.apps) // closed

        model.search = ""
        #expect(model.shownApps == model.apps) // open, nothing typed
        model.search = " ME "
        #expect(model.shownApps.map(\.source.name) == ["FaceTime", "Google Chrome"])
        model.search = "musi"
        #expect(model.shownApps.map(\.source.name) == ["Música"])
        model.search = "zoom"
        #expect(model.shownApps.isEmpty)

        model.search = "a"
        model.setOrder(AppListOrder(criterion: .name))
        #expect(model.shownApps.map(\.source.name) == ["FaceTime", "Música", "Safari"])
    }

    @Test("choosing an order is passed on once; the stored order is shown from the start")
    func appsOrderChoice() {
        let settings = UserSettings.inMemory()
        let model = makeList(settings: settings)
        #expect(model.order == .standard)

        model.setOrder(AppListOrder(criterion: .name, isReversed: true))
        model.setOrder(AppListOrder(criterion: .name, isReversed: true))
        #expect(settings.state.listOrder == AppListOrder(criterion: .name, isReversed: true))

        let stored = UserSettings.inMemory()
        stored.setListOrder(AppListOrder(criterion: .state))
        let reopened = makeList(settings: stored)
        #expect(reopened.order == AppListOrder(criterion: .state))
    }

    @Test("a click selects only that app, a second click on it alone unselects it, and a click on one of several selects only that one")
    func plainClick() {
        let model = listing().model, ids = Self.ids
        model.click(on: ids[1])
        #expect(selected(model) == [ids[1]])
        model.click(on: ids[3])
        #expect(selected(model) == [ids[3]])
        model.click(on: ids[3])
        #expect(selected(model).isEmpty)

        model.click(on: ids[0])
        model.click(on: ids[2], command: true)
        model.click(on: ids[2])
        #expect(selected(model) == [ids[2]])
    }

    @Test("⌘-click adds an app to the selection or takes it out")
    func commandClick() {
        let model = listing().model, ids = Self.ids
        model.click(on: ids[0])
        model.click(on: ids[3], command: true)
        model.click(on: ids[1], command: true)
        #expect(selected(model) == [ids[0], ids[1], ids[3]]) // in the list's order
        model.click(on: ids[0], command: true)
        #expect(selected(model) == [ids[1], ids[3]])
    }

    @Test("⇧-click selects the apps from the last one clicked, either way; a second one changes the range, keeping what ⌘ added")
    func shiftClick() {
        let model = listing().model, ids = Self.ids
        model.click(on: ids[1])
        model.click(on: ids[3], shift: true)
        #expect(selected(model) == [ids[1], ids[2], ids[3]])
        model.click(on: ids[0], shift: true) // from the same app, the other way
        #expect(selected(model) == [ids[0], ids[1]])

        model.click(on: ids[4], command: true) // where the next range starts
        model.click(on: ids[3], shift: true)
        #expect(selected(model) == [ids[0], ids[1], ids[3], ids[4]])

        model.click(on: ids[2]) // starts over
        model.click(on: ids[4], command: true, shift: true) // ⇧ with ⌘ too
        #expect(selected(model) == [ids[2], ids[3], ids[4]])
    }

    @Test("⇧-click before any click adds just that app, and the next ⇧-click selects from it")
    func shiftClickFirst() {
        let model = listing().model, ids = Self.ids
        model.click(on: ids[2], shift: true)
        #expect(selected(model) == [ids[2]])
        model.click(on: ids[4], shift: true)
        #expect(selected(model) == [ids[2], ids[3], ids[4]])

        model.click(on: ids[4]) // only this one…
        model.click(on: ids[4]) // …then none: nothing to select from
        model.click(on: ids[1], shift: true)
        #expect(selected(model) == [ids[1]])
    }

    @Test("Return or Space on a row adds it to the selection or takes it out, and a ⇧-click selects from it")
    func keyboardToggle() {
        let model = listing().model, ids = Self.ids
        model.toggleSelection(of: ids[1])
        model.toggleSelection(of: ids[3])
        #expect(selected(model) == [ids[1], ids[3]])
        model.toggleSelection(of: ids[1])
        #expect(selected(model) == [ids[3]])
        model.click(on: ids[4], shift: true)
        #expect(selected(model) == [ids[1], ids[2], ids[3], ids[4]])
    }

    @Test("Remove takes an app that pauses the music off the list at once, and its selection with it")
    func removeAppThatPauses() {
        let (model, settings) = listing()
        model.click(on: Self.ids[2])
        model.removeSelected()
        #expect(settings.state.seenApps.map(\.id) == [Self.ids[0], Self.ids[1], Self.ids[3], Self.ids[4]]) // forgotten
        #expect(model.selectedApps.isEmpty)
        #expect(model.appsAwaitingRemoval.isEmpty)
    }

    @Test("Remove takes several apps that pause the music off the list at once")
    func removeSeveralThatPause() {
        let (model, settings) = listing()
        let ids = Self.ids
        model.click(on: ids[1])
        model.click(on: ids[3], command: true)
        model.removeSelected()
        #expect(settings.state.seenApps.map(\.id) == [ids[0], ids[2], ids[4]])
        #expect(model.selectedApps.isEmpty)
        #expect(model.appsAwaitingRemoval.isEmpty)
    }

    @Test("Remove asks first for an app that's turned off: confirming forgets it, cancelling keeps it")
    func removeTurnedOffApp() {
        let zoom = AudioSource(id: "us.zoom.xos", name: "zoom.us")
        let settings = userSettings(seen: [zoom], ignored: [zoom])
        let model = makeList(settings: settings)
        show(seen: [zoom], ignored: [zoom])
        let row = model.apps[0]

        model.remove(row)
        #expect(settings.state.seenApps == [zoom]) // not yet: it's asked first
        #expect(model.appsAwaitingRemoval == [row])
        #expect(model.removalNames == ["zoom.us"])
        model.cancelRemoval()
        #expect(model.appsAwaitingRemoval.isEmpty)
        #expect(settings.state.seenApps == [zoom])

        model.click(on: row.id) // selected, the same
        model.removeSelected()
        #expect(model.appsAwaitingRemoval == [row])
        model.confirmRemoval()
        #expect(settings.state.seenApps.isEmpty && settings.state.ignoredApps.isEmpty)
        #expect(model.appsAwaitingRemoval.isEmpty)
        #expect(model.selectedApps.isEmpty)
        model.confirmRemoval() // nothing waits any more
    }

    @Test("Remove asks once for several apps when one is turned off: confirming forgets them all, cancelling keeps them")
    func removeSeveralWithTurnedOff() {
        let (model, settings) = listing(ignored: [Self.listed[2]])
        let ids = Self.ids
        model.click(on: ids[1])
        model.click(on: ids[3], shift: true)
        model.removeSelected()
        #expect(settings.state.seenApps == Self.listed) // not yet: it's asked first
        #expect(model.appsAwaitingRemoval.map(\.id) == [ids[1], ids[2], ids[3]])
        #expect(model.removalNames == ["Books", "Chess", "Discord"])
        model.cancelRemoval()
        #expect(model.appsAwaitingRemoval.isEmpty)
        #expect(model.removalNames.count == 3) // kept while the confirmation closes
        #expect(selected(model) == [ids[1], ids[2], ids[3]]) // still selected
        #expect(settings.state.seenApps == Self.listed)

        model.removeSelected()
        model.confirmRemoval()
        #expect(settings.state.seenApps.map(\.id) == [ids[0], ids[4]])
        #expect(settings.state.ignoredApps.isEmpty)
        #expect(model.selectedApps.isEmpty)
    }

    @Test("Remove from List takes its own app when it isn't one of several selected, else the whole selection, as Finder")
    func removeFromList() {
        let (model, settings) = listing()
        let ids = Self.ids, rows = model.apps
        model.click(on: ids[0])
        model.click(on: ids[1], command: true)
        model.removeFromList(rows[3]) // not selected: only it
        #expect(settings.state.seenApps.map(\.id) == [ids[0], ids[1], ids[2], ids[4]])
        #expect(selected(model) == [ids[0], ids[1]])
        model.removeFromList(rows[1]) // one of the selected: both
        #expect(settings.state.seenApps.map(\.id) == [ids[2], ids[4]])
        #expect(model.selectedApps.isEmpty)
        model.click(on: ids[2])
        model.removeFromList(rows[2]) // selected alone: itself
        #expect(settings.state.seenApps.map(\.id) == [ids[4]])
    }

    @Test("the removal's confirmation names the app for one, says how many for several, and names the one turned off when only one is")
    func removalConfirmation() {
        let (model, _) = listing(ignored: [Self.listed[2]])
        let rows = model.apps
        #expect(SoundSourcesSettingsView.removalTitle(names: ["Chess"]) == "Remove Chess from the list?")
        #expect(SoundSourcesSettingsView.removalTitle(names: ["Books", "Chess"]) == "Remove 2 apps from the list?")
        #expect(SoundSourcesSettingsView.removalMessage([rows[2]]).hasPrefix("Chess is turned off now."))
        #expect(SoundSourcesSettingsView.removalMessage([rows[1], rows[2], rows[3]]).hasPrefix("Chess is turned off now."))
        let (both, _) = listing(ignored: [Self.listed[1], Self.listed[2]])
        #expect(SoundSourcesSettingsView.removalMessage(Array(both.apps[1...2])).hasPrefix("Some of them are turned off now."))
    }

    @Test("Remove takes only the selected apps the search shows: the hidden ones stay selected, and a range skips them")
    func selectionWhileSearching() {
        let (model, settings) = listing()
        let ids = Self.ids
        model.search = "o" // Books, Discord
        model.click(on: ids[1])
        model.click(on: ids[3], shift: true)
        model.search = nil
        #expect(selected(model) == [ids[1], ids[3]]) // not Chess, hidden between them

        model.click(on: ids[0])
        model.click(on: ids[4], shift: true) // all five
        model.search = "s" // Books, Chess, Discord
        #expect(selected(model) == [ids[1], ids[2], ids[3]])
        model.removeSelected()
        #expect(settings.state.seenApps.map(\.id) == [ids[0], ids[4]])
        model.search = nil
        #expect(selected(model) == [ids[0], ids[4]])
    }

    @Test("an app the search hides isn't removed and comes back selected; closing Settings clears the selection")
    func hiddenSelection() {
        let model = listing().model, ids = Self.ids
        model.click(on: ids[4])
        model.search = "boo"
        #expect(model.selectedApps.isEmpty) // hidden: Remove is unavailable
        model.search = nil
        #expect(selected(model) == [ids[4]])
        model.clearSelection()
        #expect(model.selectedApps.isEmpty)
    }

    @Test("a click on the only selected app the search shows unselects that app alone, not the ones it hides")
    func clickKeepsHiddenSelection() {
        let model = listing().model, ids = Self.ids
        model.click(on: ids[0])
        model.click(on: ids[1], command: true)
        model.search = "arc"
        model.click(on: ids[0])
        #expect(model.selectedApps.isEmpty)
        model.search = nil
        #expect(selected(model) == [ids[1]])
    }
}
