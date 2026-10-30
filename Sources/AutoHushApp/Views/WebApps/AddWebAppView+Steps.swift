import SwiftUI
import AutoHushKit

extension AddWebAppView {
    /// Each step of adding `phase`'s web app and learning it, with where it
    /// stands, in two groups: adding the web app, then learning it, once
    /// it's made (none before). “Answer the site in Safari” comes only once
    /// the site asked something first (`siteAsked`); `learning` is the
    /// chosen player's learning, once it's made, with the countdown and note
    /// of its steps. A missing permission locks the learning ones, however
    /// many there are (pausing it by hand adds one). Until the web app made
    /// is the chosen player (`madeIsChosen`: macOS may list it a moment
    /// later), "Learn its controls" stays the step to do, since `learning` is
    /// still the previous player's.
    static func stepGroups(for phase: AddWebAppModel.Phase, siteAsked: Bool = false, closedWithoutAdding: Bool = false,
                           madeIsChosen: Bool = true, learning: LearningStatus?,
                           remaining: TimeInterval? = nil, note: LearningNote? = nil,
                           pauseMode: LearningPauseMode = .automatic, locked: Bool = false)
        -> (adding: [ChecklistStep], learning: [ChecklistStep]) {
        let check = ChecklistStep(title: String(localized: "Check the address", comment: "Add a Web App window: a step"),
                                  state: phase == .checking ? .current : .done)
        let opened = ChecklistStep(title: openStep, state: .done)
        let answered = siteAsked ? [ChecklistStep(title: answerStep, state: .done)] : []
        let learnLater = ChecklistStep(title: learnStepTitle, state: .todo)
        let learnSteps = { (name: String) in
            madeIsChosen ? Self.learningSteps(name, learning: learning, remaining: remaining, note: note,
                                              pauseMode: pauseMode, locked: locked)
                : [ChecklistStep(title: learnStepTitle, state: .current)]
        }
        switch phase {
        case .learning(let name, true):
            return ([check,
                     ChecklistStep(title: String(localized: "Already in your Dock as “\(name)”",
                                                 comment: "Add a Web App window: a step, when the website already has a web app; %@ is its name"),
                                   state: .done)],
                    learnSteps(name))
        case .learning(let name, false):
            return ([check, opened] + answered
                        + [ChecklistStep(title: String(localized: "Add it to the Dock as “\(name)”",
                                                       comment: "Add a Web App window: a step done; %@ is the web app's name"),
                                         state: .done)],
                    learnSteps(name))
        case .siteAsks(let shown, let site):
            return ([check, opened,
                    ChecklistStep(title: answerStep,
                                  notes: [String(localized: "\(shown) asks something before showing \(site) (cookies, signing in…). AutoHush goes on once it shows.",
                                                 comment: "Add a Web App window, under the step “Answer the site in Safari”; the first %@ is the site Safari shows instead (e.g. consent.example.com), the second the one typed (e.g. music.example.com)")],
                                  state: .current),
                    ChecklistStep(title: addStep, state: .todo), learnLater], [])
        case .readyToAdd(let site):
            return ([check, opened] + answered
                + [ChecklistStep(title: addStep,
                                 notes: [String(localized: "Once \(site) shows in Safari (answer anything it asks first), click Add to Dock.",
                                                comment: "Add a Web App window, under the step “Add it to the Dock”, above the Add to Dock button; %@ is the website, e.g. music.example.com")],
                                 state: .current, button: .addToDock,
                                 warning: closedWithoutAdding
                                    ? String(localized: "Safari’s window was closed without adding it. Click Add to Dock to open it again.",
                                             comment: "Add a Web App window, under the step “Add it to the Dock”, after the user closed Safari's Add to Dock window with Cancel; “Add to Dock” is the button under it")
                                    : nil),
                   learnLater], [])
        case .adding:
            return ([check, opened] + answered
                + [ChecklistStep(title: addStep,
                                 notes: [String(localized: "In Safari’s Add to Dock window, change the name if you like, then click Add.",
                                                comment: "Add a Web App window, under the step “Add it to the Dock”, while Safari's own Add to Dock window is open: the user may rename the web app there, then clicks its Add button")],
                                 state: .current),
                   learnLater], [])
        case .entering, .checking, .opening:
            return ([check,
                     ChecklistStep(title: openStep, notes: phase == .opening ? [extensionTip] : [],
                                   state: phase == .opening ? .current : phase == .checking ? .todo : .done),
                     ChecklistStep(title: addStep, state: .todo), learnLater], [])
        }
    }

    /// While Safari opens the site: an extension's request for access
    /// holds it up until it's answered.
    private static var extensionTip: String {
        String(localized: "If a Safari extension asks for access to the site, answer it first.",
               comment: "Add a Web App window, under the step “Open it in Safari” while it's under way")
    }

    private static var openStep: String {
        String(localized: "Open it in Safari", comment: "Add a Web App window: a step")
    }

    /// Only when Safari shows another site first, asking something.
    private static var answerStep: String {
        String(localized: "Answer the site in Safari",
               comment: "Add a Web App window: a step shown only when the website asks something first on another of its sites (a cookie page, signing in)")
    }

    private static var addStep: String {
        String(localized: "Add it to the Dock", comment: "Add a Web App window: a step, before it's done")
    }

    /// The learning steps, before the web app is made.
    private static var learnStepTitle: String {
        String(localized: "Learn its controls", comment: "Add a Web App window: the last step, to come, until the web app is added: AutoHush then learns which of its buttons plays and pauses it (the learning steps replace this one)")
    }

    /// Learning, once the web app is made: the learning window's two steps
    /// (both ticked once learned).
    private static func learningSteps(_ name: String, learning: LearningStatus?, remaining: TimeInterval?,
                                      note: LearningNote?, pauseMode: LearningPauseMode, locked: Bool) -> [ChecklistStep] {
        guard case .learning(let hasPlayed)? = learning else {
            return LearningSteps.steps(name: name, hasPlayed: true, hasPaused: true, locked: false, pauseMode: pauseMode)
        }
        return LearningSteps.steps(name: name, hasPlayed: hasPlayed, hasPaused: false, locked: locked,
                                   remaining: remaining, note: note, pauseMode: pauseMode)
    }
}
