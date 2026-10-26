import Foundation

/// The fades' name, wherever the app shows it: Settings → Behavior's card,
/// the checks under the media player (Settings → General, the menu's card)
/// and Diagnostics' row.
enum FadesText {
    static var title: String {
        String(localized: "Fades", comment: "Settings → Behavior: heading over the fades' switch; also, with a check, under the media player in Settings → General and in the menu's card, and a Diagnostics row: whether AutoHush can fade the media player")
    }
}
