import AppKit
import PlayerCheckKit
import AutoHushKit
import WebAppPlayers

// MARK: - Where the player bar's button was (a press goes straight to it)

/// What's kept of the app's page button between runs (`SavedButton`): in
/// button-places.json, in --caches' folder; a press goes straight to the
/// player bar's button where it was last time (`ButtonPath`), and its
/// learned recipe finds it again after its page reloads (`PlayPauseRecipe.find`).
let placesFile = cachesFolder.appendingPathComponent("button-places.json")
let savedButtonStore = SavedButtonStore(file: placesFile)
func savedButtons() -> [String: SavedButton] { savedButtonStore.all() }
func saveButton(_ change: (inout SavedButton) -> Void) { savedButtonStore.change(bundleID, change) }

/// The button's place, climbing from it to its page or window.
func placeOf(_ element: AXUIElement) -> ButtonPath? {
    var path: [Int] = [], node = element
    for _ in 0..<40 {
        let role = node.text(kAXRoleAttribute)
        if role == "AXWebArea" { return ButtonPath(root: .page, path: path.reversed()) }
        if role == kAXWindowRole { return isFlutter ? ButtonPath(root: .window, path: path.reversed()) : nil }
        guard let parent = node.value(kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
        let up = parent as! AXUIElement
        guard let index = up.children.firstIndex(where: { CFEqual($0, node) }) else { return nil }
        path.append(index)
        node = up
    }
    return nil
}

/// Remembers where the app's player bar's button is, when that changed.
func rememberPlace(of element: AXUIElement) {
    guard let found = placeOf(element), savedButtons()[bundleID]?.path != found else { return }
    saveButton { $0.path = found }
}

/// The player bar's button where it was last found, when it's still there:
/// at its path, saying the learned recipe's words (else named Play or Pause,
/// with a player's slider around it), in sight; else, with a recipe, found
/// among the page's buttons at a learned place, as AutoHush finds a learned
/// button after its page reloads (`PlayPauseRecipe.find`).
@MainActor func rememberedBarButton(pid: pid_t) -> (button: FoundButton, byPlace: Bool)? {
    guard let saved = savedButtons()[bundleID] else { return nil }
    let recipe = saved.recipe?.recipe
    let (windows, onThisDesktop) = appWindows(of: pid)
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    let hidden = app.value(kAXHiddenAttribute) as? Bool == true
    for window in windows {
        guard let path = saved.path else { break }
        AXUIElementSetMessagingTimeout(window, 1)
        guard let windowFrame = window.frame else { continue }
        for root in path.root == .window ? [window] : webAreas(in: window) {
            var node: AXUIElement? = root
            for index in path.path {
                let children = node?.children ?? []
                node = index < children.count ? children[index] : nil
            }
            guard let node, let frame = node.frame else { continue }
            let words = label(of: node)
            let says = recipe.map { $0.state(of: PageButton(handle: ButtonHandle(0), label: words)) != nil }
                ?? (named(words, playPauseWords) && playerBar(of: node) != nil)
            guard says, frame.width > 0, frame.height > 0, (windowFrame.minY...windowFrame.maxY).contains(frame.midY) else { continue }
            return (FoundButton(element: node, label: words, fromBottom: Double(windowFrame.maxY - frame.midY), inSight: true,
                                onScreen: isOnScreen(window, onThisDesktop: onThisDesktop, appHidden: hidden)), false)
        }
    }
    guard let recipe, let all = pageButtons(pid: pid) else { return nil }
    let (buttons, elements) = (all.map { PageButton(handle: ButtonHandle($0.element), label: $0.label) },
                               Dictionary(all.map { (ButtonHandle($0.element), $0) }, uniquingKeysWith: { first, _ in first }))
    guard let found = recipe.find(in: buttons, place: webPage.place(of:)), let button = elements[found.handle] else { return nil }
    rememberPlace(of: button.element)
    return (button, true)
}

/// For a press: takes the player bar's button where it was last time as
/// the page's Play/Pause, when it's still there (turning on the switch an
/// Electron, CEF or Flutter app needs, so the page stays up to date).
@MainActor func useRememberedBar(pid: pid_t) -> Bool {
    guard let (found, byPlace) = rememberedBarButton(pid: pid) else { return false }
    if let hidden = hiddenInterface { pageSwitch = hidden.switches.first { turnOn($0, pid: pid, pageReadable: true) } }
    page = PageCheck(buttons: 1, toggle: found, withControls: true)
    barToggle = found.element
    pageRead = true
    pageNotChecked = nil
    say("  its player bar's \(shown(found.label)), " + (byPlace ? "found at its learned place (its page changed since)" : "where it was last time"))
    return true
}

// MARK: - Learning the page's Play/Pause, as AutoHush learns a web app's

/// AutoHush's own page reader, for a button's place and standing (`place`,
/// `standing`): any app's page, on any desktop, a Flutter app's items too.
let webPage = AccessibilityWebPage()
/// Learns the button whose words changed between a look while the app plays
/// and one once it paused (`PlayPauseLearner`), as AutoHush learns a web
/// app's from its It's Playing and It's Paused; here the pause is a
/// test's, by any way, or, with no other, one by whoever runs the check.
@MainActor var learner = PlayPauseLearner()
/// The recipe learned in this run, and its button; the one learned before.
@MainActor var learned: (recipe: PlayPauseRecipe, element: AXUIElement)?
@MainActor let savedRecipe = savedButtons()[bundleID]?.recipe?.recipe
@MainActor var learningSaid = false
/// Set when a look for learning found the page out of sight.
@MainActor var learningOutOfSight = false

let outOfSightWhy = "its window is out of sight, where a Chromium or Flutter page's words lag a state behind"

/// The page's buttons as AutoHush's learning takes them, and each one found
/// by its handle: only those whose words are current (`wordsCurrent`), as a
/// Chromium page out of sight lags a state, and its words would be learned
/// the wrong way round. `outOfSight`: it has buttons, but none current.
@MainActor func learningButtons(_ pid: pid_t) -> (buttons: [PageButton], found: [ButtonHandle: FoundButton], outOfSight: Bool) {
    let all = pageButtons(pid: pid) ?? []
    var found: [ButtonHandle: FoundButton] = [:]
    let buttons = all.filter(wordsCurrent).map { button -> PageButton in
        let handle = ButtonHandle(button.element)
        found[handle] = button
        return PageButton(handle: handle, label: button.label, isEnabled: button.element.value(kAXEnabledAttribute) as? Bool ?? true)
    }
    return (buttons, found, buttons.isEmpty && !all.isEmpty)
}

/// Says once that the page's Play/Pause isn't learned, and why.
@MainActor func sayNotLearned(_ why: String) {
    guard !learningSaid else { return }
    learningSaid = true
    say("    its page's Play/Pause not learned: \(why)")
}

/// Takes the look while it plays, once a test has it playing (`ready`):
/// not while its page is out of sight (taken at the next test instead).
@MainActor func noteLearningPlaying(pid: pid_t) {
    guard page?.buttons ?? 0 > 0, !learner.hasPlayed, learned == nil else { return }
    let look = learningButtons(pid)
    learningOutOfSight = look.outOfSight
    guard !look.outOfSight else { return }
    learner.notePlaying(look.buttons, at: Date())
}

/// Once a test paused it (by any way): the button whose words changed is
/// learned (`PlayPauseLearner.recipe`: in sight, with a player's controls,
/// the barest words, the lowest), saved merged with what was learned before,
/// and pressed by the page way from then on. Said once when nothing changed.
@MainActor func learnPageButton(pid: pid_t) {
    guard learned == nil else { return }
    guard learner.hasPlayed else {
        if learningOutOfSight { sayNotLearned(outOfSightWhy) }
        return
    }
    let (buttons, found, outOfSight) = learningButtons(pid)
    if outOfSight { return sayNotLearned(outOfSightWhy) }
    let placed = learner.candidates(paused: buttons).compactMap { candidate in
        webPage.place(of: candidate.handle).flatMap { place in webPage.standing(of: candidate.handle).map { (candidate, place, $0) } }
    }
    guard let (recipe, handle) = PlayPauseLearner.recipe(from: placed), let button = found[handle] else {
        return sayNotLearned("none of its buttons changed words")
    }
    let element = button.element
    let merged = savedRecipe?.merging(recipe) ?? recipe
    learned = (merged, element)
    saveButton { saved in
        saved.recipe = SavedRecipe(merged)
        if let path = placeOf(element) { saved.path = path }
    }
    let guess = page?.toggle
    let same = guess.map { CFEqual($0.element, element) }
    say("    learned its page's Play/Pause, as AutoHush learns a web app's: \(shown(recipe.pauseLabel)) while it plays, \(shown(recipe.playLabel))"
        + " while paused, \(Int(recipe.places[0].distanceFromBottom)) pt from the window's bottom"
        + (same == true ? " (the button this tool found)" : guess.map { " (not \(shown($0.label)), the one this tool found)" } ?? ""))
    if same != true {
        page = PageCheck(buttons: page?.buttons ?? buttons.count,
                         toggle: FoundButton(element: element, label: label(of: element), fromBottom: recipe.places[0].distanceFromBottom,
                                             inSight: true, onScreen: button.onScreen),
                         withControls: placed.first { $0.0.handle == handle }?.2.isWithPlayerControls ?? false)
        barToggle = element
    }
}

/// After a press by the page that took: what the pressed button said before
/// and after it is learned, as AutoHush learns a button again once it went
/// missing, merged with what was learned before. Only while its words are
/// current (`wordsCurrent`): out of sight, a Chromium page's lag one state,
/// and would be saved the wrong way round ('Pause' as the word for paused),
/// replacing the right ones (`merging` keeps only the newer words).
@MainActor func learnFromPress(_ button: FoundButton, before: String, pausing: Bool) {
    guard wordsCurrent(button) else { return }
    let element = button.element
    let after = label(of: element)
    guard !before.isEmpty, !after.isEmpty, before != after, let place = webPage.place(of: ButtonHandle(element)) else { return }
    let recipe = PlayPauseRecipe(playLabel: pausing ? after : before, pauseLabel: pausing ? before : after, places: [place])
    saveButton { $0.recipe = SavedRecipe($0.recipe.map { $0.recipe.merging(recipe) } ?? recipe) }
}
