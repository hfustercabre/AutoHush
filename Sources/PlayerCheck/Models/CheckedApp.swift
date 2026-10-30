import AutoHushKit
import Foundation

/// The app checked or pressed, as its bundle names it.
struct CheckedApp: Sendable {
    let url: URL
    let bundleID: String
    let name: String
    let version: String

    static let found: CheckedApp = {
        guard let url = findApp(target), let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            fail("no app found for \(target)")
        }
        let info = bundle.infoDictionary ?? [:]
        return CheckedApp(url: url, bundleID: id, name: AppName.of(appAt: url),
                          version: info["CFBundleShortVersionString"] as? String ?? "?")
    }()
}
