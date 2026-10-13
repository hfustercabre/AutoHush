import Observation

/// The one place the app's status is kept (see GLOSSARY.md). AppDelegate
/// writes it; Settings and the welcome, learning and Add a Web App windows
/// read it through their model; the menu gets a copy each time it changes.
@MainActor
@Observable
final class AppState {
    var status = AppStatus()
}
