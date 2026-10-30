/// Which row to press: the app's (`PanelRead.row`), the row it changed
/// with before (kept between runs) as the one AutoHush remembers; the same
/// with the row pressed last as that one (a trial's play, after its pause
/// pressed it); or only the one pressed last (to put back a press that
/// changed it).
enum PanelRowChoice { case app, lastElseApp, lastOnly }
