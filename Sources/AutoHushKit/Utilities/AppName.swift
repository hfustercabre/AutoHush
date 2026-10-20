import Foundation

/// An app's name as the user sees it in Finder and the Dock, in their
/// language: Finder's display name of its bundle, without ".app". The one
/// name AutoHush reads for an app wherever it reads one (the user,
/// 2026-10-20: the bundle's own names gave one app two names).
package enum AppName {
    package static func of(appAt url: URL) -> String {
        let shown = FileManager.default.displayName(atPath: url.path)
        let name = shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
        return name.isEmpty ? url.deletingPathExtension().lastPathComponent : name
    }
}
