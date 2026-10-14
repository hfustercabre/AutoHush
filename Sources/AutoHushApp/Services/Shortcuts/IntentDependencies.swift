import AppIntents

/// What Shortcuts' actions and the Focus filter reach through `@Dependency`.
/// Registered in AppDelegate's init, before launch finishes, since macOS may
/// open AutoHush just to run one of them.
enum IntentDependencies {
    /// A second registration replaces the first: App Intents keeps one value
    /// per type (each AppDelegate in the tests registers its own).
    @MainActor
    static func register(control: any AutoPauseControlling, focus: FocusAutoPause) {
        AppDependencyManager.shared.add(dependency: control)
        AppDependencyManager.shared.add(dependency: focus)
    }
}
