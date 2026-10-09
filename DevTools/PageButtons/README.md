# PageButtons

Lists or presses the buttons of the web pages in an app's windows (Safari,
or a Safari web app such as YouTube Music), by their names, the way AutoHush
reads them. Used in tests to play and pause a web app like a user would,
and to answer a page (a cookie notice, for example).

```bash
swiftc -O -o pagebuttons DevTools/PageButtons/pagebuttons.swift
./pagebuttons "YT Music" list Reproducir Pausar       # buttons starting with these words
./pagebuttons "YT Music" press Pausar                 # the lowest button named exactly that
./pagebuttons "YT Music" press-prefix "Reproducir "   # the highest song card, say
./pagebuttons Safari list --links                     # links count too
./pagebuttons Safari list Play Pause --path           # what surrounds each one
```

`<app>` is the app's name, bundle ID or process ID. Each button is shown
with its distance from the window's bottom (players keep their controls at
the bottom) and whether it's disabled.

## How it works

It finds the app's windows through Accessibility (`kAXWindowsAttribute`;
for windows on another desktop, `_AXUIElementCreateWithRemoteToken`, a
private function, within one second), then each window's page
(`AXWebArea`), and asks WebKit for every button in it with
`AXUIElementsForSearchPredicate` (`AXButtonSearchKey`, and
`AXLinkSearchKey` with `--links`). A button's name is its description,
else its title, as AutoHush reads it; a button with neither shows the text
inside it, marked "AutoHush sees no name", since AutoHush can't learn it by
that. A button without a frame (probably hidden) is pressed only when no
other matches. `press` sends `AXPress`. The process needs the
Accessibility permission.

With `--path`, each listed button is followed by what surrounds it, its
parent first: each element's role (and subrole), its first CSS class
(`AXDOMClassList`), and `[slider]` when a slider or progress bar is inside
it, as a player's controls have. Used to see how a site's player bar
differs from its other Play buttons.

