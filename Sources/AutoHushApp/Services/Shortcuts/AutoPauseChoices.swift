import AppIntents
import Foundation
import AutoHushKit

/// Set Auto-Pause's choice: on, off, or the other of the two.
enum AutoPauseOperation: String, AppEnum {
    case turnOn
    case turnOff
    case toggle

    // The same name as the parameter's title, which is the one Shortcuts shows.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "On or Off",
            comment: "Shortcuts, Set Auto-Pause: the name of its choice (On, Off or Toggle), shown when the choice is asked each time (it reads “Turn Auto-Pause On or Off”); it’s also shown alone, as the placeholder of an empty field in Spotlight")
    )

    static let caseDisplayRepresentations: [AutoPauseOperation: DisplayRepresentation] = [
        .turnOn: DisplayRepresentation(title: LocalizedStringResource(
            "On", comment: "A setting that is on: in Diagnostics, and the choice that turns Auto-Pause on in Shortcuts (it reads “Turn Auto-Pause On”) and in the Focus filter")),
        .turnOff: DisplayRepresentation(title: LocalizedStringResource(
            "Off", comment: "A setting that is off: in Diagnostics, and the choice that turns Auto-Pause off in Shortcuts (it reads “Turn Auto-Pause Off”) and in the Focus filter")),
        .toggle: DisplayRepresentation(title: LocalizedStringResource(
            "Toggle",
            comment: "Shortcuts, Set Auto-Pause: the choice that turns Auto-Pause off if it’s on, and on if it isn’t (it reads “Toggle Auto-Pause”)")),
    ]

    /// On also ends a "turn off for", as the menu's switch does; Off lasts
    /// until Auto-Pause is turned on again.
    @MainActor
    func apply(to control: any AutoPauseControlling, now: Date = Date()) {
        switch self {
        case .turnOn: control.setAutoPause(true)
        case .turnOff: control.setAutoPause(false)
        case .toggle: control.toggleAutoPause(now: now)
        }
    }
}

/// Turn Off Auto-Pause For's choice: the menu's "Turn off for" durations,
/// with the menu's full titles, so their translations are shared.
enum AutoPauseDuration: String, AppEnum {
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twentyFourHours

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "Duration", comment: "Shortcuts, Turn Off Auto-Pause For: the name of its choice of how long Auto-Pause stays off")
    )

    // The same keys and comments as `AutoPauseSnooze.title`.
    static let caseDisplayRepresentations: [AutoPauseDuration: DisplayRepresentation] = [
        .fiveMinutes: DisplayRepresentation(title: LocalizedStringResource(
            "5 Minutes", comment: "In the menu: turn auto-pause off for 5 minutes")),
        .fifteenMinutes: DisplayRepresentation(title: LocalizedStringResource(
            "15 Minutes", comment: "In the menu: turn auto-pause off for 15 minutes")),
        .thirtyMinutes: DisplayRepresentation(title: LocalizedStringResource(
            "30 Minutes", comment: "In the menu: turn auto-pause off for 30 minutes")),
        .oneHour: DisplayRepresentation(title: LocalizedStringResource(
            "1 Hour", comment: "In the menu: turn auto-pause off for 1 hour")),
        .twentyFourHours: DisplayRepresentation(title: LocalizedStringResource(
            "24 Hours", comment: "In the menu: turn auto-pause off for 24 hours")),
    ]

    /// The menu's choice of the same name.
    var snooze: AutoPauseSnooze {
        switch self {
        case .fiveMinutes: .fiveMinutes
        case .fifteenMinutes: .fifteenMinutes
        case .thirtyMinutes: .thirtyMinutes
        case .oneHour: .oneHour
        case .twentyFourHours: .twentyFourHours
        }
    }
}

// The two choices' lists and defaults come from the app, not from the
// metadata. Spotlight (macOS 27) shows a metadata default as its raw value
// ("turnOff"; Apple's Voice Memos shows "mostRecent" the same way) and lists
// a metadata enum's cases sorted by raw value. From these providers it gets
// the cases in their order and the default by its title. macOS opens a quit
// AutoHush in the background to ask them, as it does to run an action.

/// Set Auto-Pause's choices, in order, starting on Off.
struct AutoPauseOperationOptions: DynamicOptionsProvider {
    func results() async throws -> [AutoPauseOperation] { AutoPauseOperation.allCases }
    func defaultResult() async -> AutoPauseOperation? { .turnOff }
}

/// Turn Off Auto-Pause For's durations, shortest first, starting on 15 Minutes.
struct AutoPauseDurationOptions: DynamicOptionsProvider {
    func results() async throws -> [AutoPauseDuration] { AutoPauseDuration.allCases }
    func defaultResult() async -> AutoPauseDuration? { .fifteenMinutes }
}
