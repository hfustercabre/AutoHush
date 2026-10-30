/// What the page showed: how many buttons (0: none), and the player's
/// Play/Pause, with or without a player's slider around it (without, it's
/// likely a song's own button: nothing loaded, or nobody signed in).
struct PageCheck {
    let buttons: Int
    let toggle: FoundButton?
    var withControls = false
}
