import AppKit

extension NSRunningApplication {
    /// The app running with `bundleID`, unless it's quitting; `nil` while
    /// none runs.
    static func running(_ bundleID: String) -> NSRunningApplication? {
        runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }
}
