import AppIntents

// AutoHush's Focus filter: Auto-Pause on or off during a Focus, put back
// after it (`FocusAutoPause`). macOS calls `perform()` with the choice when
// a Focus with the filter turns on, and with none when it ends or another
// Focus without it takes over. It doesn't open a quit AutoHush for either, so
// the launch reads `current` too (`currentChoice()`, from AppDelegate). The
// texts are compile-time literals, as for the actions (AutoPauseIntents.swift).

/// The filter's choice: Auto-Pause on or off during the Focus.
enum AutoPauseFocusChoice: String, AppEnum {
    case on
    case off

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Auto-Pause", comment: "Auto-Pause, the feature's name: the switch's label in the menu's card and Settings → General, a Diagnostics row, the Focus filter's name, and the name of the Focus filter's On/Off choice")
    )

    static let caseDisplayRepresentations: [AutoPauseFocusChoice: DisplayRepresentation] = [
        .on: DisplayRepresentation(title: LocalizedStringResource(
            "On", comment: "A setting that is on: in Diagnostics, and the choice that turns Auto-Pause on in Shortcuts (it reads “Turn Auto-Pause On”) and in the Focus filter")),
        .off: DisplayRepresentation(title: LocalizedStringResource(
            "Off", comment: "A setting that is off: in Diagnostics, and the choice that turns Auto-Pause off in Shortcuts (it reads “Turn Auto-Pause Off”) and in the Focus filter")),
    ]

    var isOn: Bool { self == .on }
}

/// Turns Auto-Pause on or off while a Focus is on, and puts it back when the
/// Focus ends, unless the user changed it meanwhile.
struct AutoPauseFocusFilter: SetFocusFilterIntent {
    static let title = LocalizedStringResource(
        "Auto-Pause", comment: "Auto-Pause, the feature's name: the switch's label in the menu's card and Settings → General, a Diagnostics row, the Focus filter's name, and the name of the Focus filter's On/Off choice")
    static let description: IntentDescription? = IntentDescription(LocalizedStringResource(
        "Turns Auto-Pause on or off during this Focus. When the Focus ends, Auto-Pause goes back to how it was, unless you changed it meanwhile.",
        comment: "Focus filter: what it does, in System Settings, once added to a Focus"))

    // Optional with no default: a Focus's end arrives as nil (a default would
    // probably arrive instead, and the end couldn't be told apart).
    @Parameter(title: LocalizedStringResource("Auto-Pause", comment: "Auto-Pause, the feature's name: the switch's label in the menu's card and Settings → General, a Diagnostics row, the Focus filter's name, and the name of the Focus filter's On/Off choice"))
    var choice: AutoPauseFocusChoice?

    @Dependency private var focus: FocusAutoPause

    init() {}

    /// How the Focus's settings list the filter once it's added.
    var displayRepresentation: DisplayRepresentation {
        switch choice {
        case .on:
            DisplayRepresentation(title: LocalizedStringResource(
                "Auto-Pause On",
                comment: "Shortcuts and Focus: Auto-Pause turned on (a Focus filter's setting, an App Shortcut's title)"))
        case .off:
            DisplayRepresentation(title: LocalizedStringResource(
                "Auto-Pause Off",
                comment: "Shortcuts and Focus: Auto-Pause turned off (a Focus filter's setting, an App Shortcut's title)"))
        case nil:
            DisplayRepresentation(title: Self.title)
        }
    }

    /// What `FocusAutoPause` follows: true = Auto-Pause on, nil = no Focus
    /// with the filter (or one added without a choice).
    static func choice(of filter: AutoPauseFocusFilter) -> Bool? {
        filter.choice?.isOn
    }

    /// The choice of the filter macOS reports now, as `choice(of:)` gives it,
    /// read at launch. Throws when macOS can't report it.
    static func currentChoice() async throws -> Bool? {
        choice(of: try await current)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        focus.follow(Self.choice(of: self))
        return .result()
    }
}
