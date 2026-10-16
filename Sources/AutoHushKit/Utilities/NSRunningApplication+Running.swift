import AppKit

extension NSRunningApplication {
    /// The app running with `bundleID`, unless it's quitting; `nil` while
    /// none runs. The players and the permissions ask it the same way.
    package static func running(_ bundleID: String) -> NSRunningApplication? {
        runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }

    /// The app as AutoHush lists it (its name and icon, as the monitoring
    /// finds them), or `nil` without a bundle.
    package var audioSource: AudioSource? {
        bundleURL.flatMap(ProcessAudioSourceIdentifier.source(forBundleAt:))
    }
}
