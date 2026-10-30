import AppKit
import AutoHushKit
import WebAppPlayers

// MARK: - Pressing its page's button

/// Presses a page button, as AutoHush's web apps press theirs: never one the
/// site disabled (during an ad, it can't be paused: AutoHush mutes the app
/// instead, which a one-off press can't hold); `why` says so.
@MainActor func pressPageButton(_ button: FoundButton, pausing: Bool, why: inout String?) -> Bool {
    if button.element.value(kAXEnabledAttribute) as? Bool == false {
        why = "its page's \(shown(button.label)) is disabled (sites disable it during ads): not pressed"
            + (pausing ? "; AutoHush would mute it instead" : "")
        return false
    }
    if let pid = running?.processIdentifier { waitForFullerMode(pid: pid) }
    return AXUIElementPerformAction(button.element, kAXPressAction as CFString) == .success
}

/// The page's button to press to pause (or play): the player bar's button
/// with that word; else, when the app's state is known (by script, else as
/// it reports to Now Playing), the bar's button whatever its word, since it
/// toggles (a Chromium page on another desktop keeps its word: Play while
/// it plays); else one with that word.
@MainActor func pageButtonToPress(pid: pid_t, pausing: Bool) -> FoundButton? {
    let wanted: PlayerState = pausing ? .playing : .paused // what its words say when it's the one to press
    // The button learned in this run, as AutoHush presses a web app's: when
    // its words say what's wanted, or it toggles while its scripted state or report tells how it is.
    if let learned {
        let words = label(of: learned.element)
        let says = learned.recipe.state(of: PageButton(handle: ButtonHandle(0), label: words))
        if says == wanted || (says != nil && (scriptedState() != nil || reportedState() != nil)) {
            return FoundButton(element: learned.element, label: words, fromBottom: nil, inSight: true, onScreen: page?.toggle?.onScreen ?? true)
        }
    }
    // A press takes the player bar's button the page section found (where
    // it was last time, or at its learned place), read again by its words
    // (no new search, no hit tests): when it says what's wanted, or toggles
    // while the app reports how it is.
    if pressingOneWay, page?.withControls == true, let bar = page?.toggle {
        let words = label(of: bar.element)
        let found = FoundButton(element: bar.element, label: words, fromBottom: bar.fromBottom, inSight: bar.inSight, onScreen: bar.onScreen)
        if wordSays(words) == wanted { return found }
        if !barShowsState, wordSays(words) != nil, scriptedState() != nil || reportedState() != nil { return found }
    }
    let named = playerButton(pid: pid, named: pausing ? pauseWords : playWords)
    if let named, named.withControls { return named.button }
    if scriptedState() != nil || reportedState() != nil, let bar = playerButton(pid: pid, named: playPauseWords), bar.withControls {
        return bar.button
    }
    return named?.button
}
