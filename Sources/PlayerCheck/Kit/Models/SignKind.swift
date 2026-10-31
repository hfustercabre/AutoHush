/// The signs of whether it plays, surest first, in the order AutoHush reads
/// an added app's (`CheckedPlayer.sureState`), so what a check approves is
/// what AutoHush will do (the user, 2026-10-26): its scripted state, its
/// page's Play/Pause (while its word is current), its menu's state (as
/// AutoHush's MenuPlayer reads it), what it reports to Now Playing, then
/// its level (as AutoHush hears it) and its keep-awake assertion (as
/// AntiDot mode reads it). A menu's word may change late by itself (one
/// said Play while playing, then Pause a second later, with nothing
/// pressed); it comes before the report all the same, as in AutoHush.
package enum SignKind: CaseIterable, Sendable { case script, page, menu, report, level, awake }
