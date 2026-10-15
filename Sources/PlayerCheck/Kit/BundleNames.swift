import AppKit

/// An app's name as its bundle says it, by its bundle ID, wherever Launch
/// Services finds it: a Chromium web app's browser, say ("Google Chrome").
package enum BundleNames {
    package static func name(of bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).flatMap { Bundle(url: $0)?.infoDictionary }
            .flatMap { ($0["CFBundleDisplayName"] ?? $0["CFBundleName"]) as? String } ?? bundleID
    }
}
