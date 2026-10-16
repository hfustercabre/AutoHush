import AppIntents
import Foundation
import AutoHushKit

// Shortcuts' three actions for Auto-Pause. They act on the running AutoHush
// (macOS opens it in the background first when it isn't running, so
// `openAppWhenRun` stays false) through `AutoPauseControlling`, registered at
// launch (`IntentDependencies`). Their texts are compile-time literals: the
// build's metadata step reads them from the source, not from the running app.

/// Turns Auto-Pause on or off, or toggles it.
struct SetAutoPauseIntent: AppIntent {
    static let title = LocalizedStringResource(
        "Set Auto-Pause", comment: "Shortcuts: the name of the action that turns Auto-Pause on or off, or toggles it")
    static let description: IntentDescription? = IntentDescription(LocalizedStringResource(
        "Turns Auto-Pause on or off, or toggles it. Off lasts until Auto-Pause is turned on again.",
        comment: "Shortcuts: what the Set Auto-Pause action does"))

    @Parameter(
        title: LocalizedStringResource(
            "On or Off",
            comment: "Shortcuts, Set Auto-Pause: the name of its choice (On, Off or Toggle), shown when the choice is asked each time (it reads “Turn Auto-Pause On or Off”); it’s also shown alone, as the placeholder of an empty field in Spotlight"),
        optionsProvider: AutoPauseOperationOptions())
    var operation: AutoPauseOperation

    static var parameterSummary: some ParameterSummary {
        When(\.$operation, .equalTo, .toggle) {
            Summary("\(\.$operation) Auto-Pause")
        } otherwise: {
            Summary("Turn Auto-Pause \(\.$operation)")
        }
    }

    @Dependency private var control: any AutoPauseControlling

    init() {}

    init(operation: AutoPauseOperation) {
        self.operation = operation
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        operation.apply(to: control)
        return .result()
    }
}

/// Turns Auto-Pause off for one of the menu's durations; it comes back on by
/// itself.
struct TurnOffAutoPauseForIntent: AppIntent {
    static let title = LocalizedStringResource(
        "Turn Off Auto-Pause For",
        comment: "Shortcuts: the name of the action that turns Auto-Pause off for a while, as the menu’s “Turn off for” buttons do")
    static let description: IntentDescription? = IntentDescription(LocalizedStringResource(
        "Turns Auto-Pause off for a while. It comes back on by itself, as with the menu’s buttons.",
        comment: "Shortcuts: what the Turn Off Auto-Pause For action does"))

    @Parameter(
        title: LocalizedStringResource(
            "Duration", comment: "Shortcuts, Turn Off Auto-Pause For: the name of its choice of how long Auto-Pause stays off"),
        optionsProvider: AutoPauseDurationOptions())
    var duration: AutoPauseDuration

    static var parameterSummary: some ParameterSummary {
        Summary("Turn off Auto-Pause for \(\.$duration)")
    }

    @Dependency private var control: any AutoPauseControlling

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        control.snooze(duration.snooze, now: Date())
        return .result()
    }
}

/// Whether Auto-Pause is on now: false while it's off or turned off for a while.
struct GetAutoPauseIntent: AppIntent {
    static let title = LocalizedStringResource(
        "Get Auto-Pause", comment: "Shortcuts: the name of the action that tells whether Auto-Pause is on")
    static let description: IntentDescription? = IntentDescription(LocalizedStringResource(
        "Tells whether Auto-Pause is on now. It isn’t while it’s off or turned off for a while.",
        comment: "Shortcuts: what the Get Auto-Pause action does"))

    @Dependency private var control: any AutoPauseControlling

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: control.isAutoPauseActive)
    }
}
