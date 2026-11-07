import Testing
@testable import AutoHushApp

/// Settings → Sound Sources' search, as the page makes it.
@Suite("SoundSourcesSettingsView")
@MainActor
struct SoundSourcesSettingsViewTests {
    @Test("its search's ✕ closes it, empty or not, and a click in its field does nothing to it (K3-1: the trailing closure was a click's)")
    func searchCloses() throws {
        let model = SettingsModel.forTests(actions: FakeAppActions())
        model.appList.search = ""
        let field = SoundSourcesSettingsView.searchField(model.appList)
        #expect(field.onClick == nil) // a click in it only focuses it
        let close = try #require(field.onClose) // "Close search", not "Clear search", which only empties it
        model.appList.search = "chr"
        close()
        #expect(model.appList.search == nil)
    }
}
