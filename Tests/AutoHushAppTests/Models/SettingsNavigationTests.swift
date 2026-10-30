import Testing
@testable import AutoHushApp

@Suite("SettingsNavigation")
@MainActor
struct SettingsNavigationTests {
    @Test("each page shown can be gone back to; Forward undoes Back until another page is shown")
    func history() {
        let sut = SettingsNavigation()
        var shown: [SettingsPage] = []
        sut.onChange = { shown.append($0) }
        sut.page = .behavior
        sut.page = .fineTuning
        sut.page = .fineTuning // the same page: nothing to go back to
        #expect(sut.back == [.general, .behavior] && sut.forward.isEmpty)

        sut.goBack()
        sut.goBack()
        #expect(sut.page == .general && !sut.canGoBack && sut.forward == [.fineTuning, .behavior])
        sut.goBack() // nothing before: stays
        #expect(sut.page == .general)
        sut.goForward()
        #expect(sut.page == .behavior && sut.canGoBack && sut.canGoForward)

        sut.page = .about // another page: Forward's are gone
        #expect(sut.back == [.general, .behavior] && !sut.canGoForward)
        #expect(shown == [.behavior, .fineTuning, .behavior, .general, .behavior, .about])

        sut.clearHistory()
        #expect(!sut.canGoBack && !sut.canGoForward && sut.page == .about)
    }
}
