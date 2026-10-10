import AppKit
import AutoHushKit

/// Settings → Diagnostics: what AutoHush sees, kept up to date while the tab
/// shows.
extension AppDelegate {
    /// Brings Settings → Diagnostics up to date with what AutoHush sees.
    func refreshDiagnostics() {
        // Only apps with a known path: the others are looked up.
        let known = Dictionary(
            settingsModel.apps.compactMap { app in app.source.bundlePath.map { (app.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let snapshot = DiagnosticsReport.snapshot(
            activeAudio: pipeline?.activeAudioReport() ?? [], status: status, facts: diagnosticsFacts(),
            bundlePath: { id in known[id] ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path }
        )
        if settingsModel.diagnostics != snapshot { settingsModel.diagnostics = snapshot }
    }

    /// What Diagnostics shows besides the apps with sound.
    private func diagnosticsFacts() -> DiagnosticsFacts {
        let permission = player?.controlPermission
        // Accessibility can be read; Automation only shows when AutoHush uses it.
        let granted: Bool? = switch permission {
        case .accessibility?: AccessibilityPermission.isTrusted()
        case let permission?: status.health == .needsPermission(permission) ? false : (status.isReady ? true : nil)
        case nil: nil
        }
        return DiagnosticsFacts(
            playerVersion: status.chosenPlayer?.appURL.flatMap {
                Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            },
            playerCanFade: settingsModel.playerCanFade,
            playerPermission: permission,
            playerPermissionGranted: granted,
            playerLearned: (player as? any LearningMusicPlayer).map { $0.learningStatus.isLearned },
            reachesOtherSpaces: player?.kind == .safariWebApp ? AccessibilityWindows.isAvailable : nil,
            playerWordsRead: player?.ownWordsRead,
            audioRecording: TCCAudioCapturePermission().status(),
            notificationsOff: settingsModel.notificationsOff,
            detectionMethod: preferences.detectionMethod,
            timings: preferences.timings,
            appVersion: settingsModel.fullVersion ?? "",
            launchAtLogin: settingsModel.launchAtLoginEnabled,
            checksForUpdates: settingsModel.checksForUpdatesAutomatically,
            automaticUpdates: settingsModel.automaticUpdates,
            lastUpdateCheck: settingsModel.lastUpdateCheck,
            macOS: Self.macOSVersion,
            processor: Self.processor
        )
    }

    /// E.g. "27.0.1 (26A434)".
    private static let macOSVersion: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let number = [version.majorVersion, version.minorVersion, version.patchVersion]
            .enumerated().filter { $0.offset < 2 || $0.element > 0 }.map { String($0.element) }.joined(separator: ".")
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return number }
        var build = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &build, &size, nil, 0) == 0 else { return number }
        return "\(number) (\(String(decoding: build.prefix { $0 != 0 }, as: UTF8.self)))"
    }()

    /// "Apple silicon", also for an Intel build running under Rosetta, or "Intel".
    private static let processor: String = {
        var arm64: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &arm64, &size, nil, 0) == 0 && arm64 == 1 ? "Apple silicon" : "Intel"
    }()
}
