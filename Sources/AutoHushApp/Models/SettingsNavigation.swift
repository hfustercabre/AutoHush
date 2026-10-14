import Observation

/// Which page Settings shows; the window's title follows it.
@MainActor
@Observable
final class SettingsNavigation {
    var page = SettingsWindowController.Page.general {
        didSet { if page != oldValue { onChange?(page) } }
    }
    @ObservationIgnored var onChange: ((SettingsWindowController.Page) -> Void)?
}
