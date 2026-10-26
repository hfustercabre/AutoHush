import Foundation

/// "None": no apps, or no ignored apps (Diagnostics), and the menu's
/// Ignored Apps while no app is ignored.
enum NoneText {
    static var title: String {
        String(localized: "None", comment: "Diagnostics: no apps, or no ignored apps; the menu's Ignored Apps while no app is ignored")
    }
}
