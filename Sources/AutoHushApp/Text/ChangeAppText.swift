import Foundation

/// The question Add an App's Change… asks once the check has run (the user,
/// 2026-10-18: "Ask first"): `PlayerAlerts.changeApp`.
enum ChangeAppText {
    static var title: String {
        String(localized: "Choose another app?", comment: "Add an App window: title of the question Change… asks once the check has run")
    }

    static func discards(_ app: String) -> String {
        String(localized: "What the check found for \(app) is forgotten.",
               comment: "Add an App window: what Change… does once the check has run, in its question; %@ is the checked app")
    }

    static var confirm: String {
        String(localized: "Choose Another App", comment: "Add an App window: the button that confirms Change… once the check has run, forgetting what it found")
    }
}
