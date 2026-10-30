import AutoHushKit
import CheckedPlayers
import PlayerCheckKit
import Foundation

/// What the Add an App window (W2), the warning before its check (W6) and
/// the check's panel say. `app` is the chosen app's name. What other places
/// say too is in `Text/` (`ButtonText`, `ChangeAppText`, `ReopenText`,
/// `WayText`).
enum AddAppText {
    // MARK: - The window

    static var description: String {
        String(localized: "AutoHush checks how it can pause and play an app it doesn’t support yet, so that app can be your player.",
               comment: "Add an App window, at its top beside AutoHush's icon")
    }

    static var stepsHeading: String {
        String(localized: "How the Check Goes", comment: "Add an App window: the heading over its numbered steps")
    }

    // MARK: Step 1: the app

    static var chooseTitle: String {
        String(localized: "Choose the app", comment: "Add an App window: the first step's title")
    }

    static var chooseNote: String {
        String(localized: "One that plays music, podcasts or videos. If it isn’t open, AutoHush opens it in the background.",
               comment: "Add an App window, under the step “Choose the app”")
    }

    static func chosen(_ app: String, traits: CheckedAppTraits?, browser: String? = nil) -> String {
        switch traits?.framework {
        case .electron?: String(localized: "\(app), built with Electron", comment: "Add an App window, under the step “Choose the app” once done; %@ is the app")
        case .chromium?: String(localized: "\(app), built with Chromium", comment: "Add an App window, under the step “Choose the app” once done; %@ is the app")
        case .flutter?: String(localized: "\(app), built with Flutter", comment: "Add an App window, under the step “Choose the app” once done; %@ is the app")
        case .browserWebApp?:
            browser.map { browser in String(localized: "\(app), a web app of \(browser)", comment: "Add an App window, under the step “Choose the app” once done: a web app made by Chrome or another Chromium browser; the first %@ is the app, the second the browser, e.g. Brave Browser") }
                ?? String(localized: "\(app), a browser’s web app", comment: "Add an App window, under the step “Choose the app” once done: a web app of Chrome or another Chromium browser; %@ is the app")
        case nil: app
        }
    }

    static func opening(_ app: String) -> String {
        String(localized: "Opening \(app)…", comment: "Add an App window, under the step “Choose the app” while the chosen app opens in the background, and under “Play something” while it opens again after it quit; %@ is the app")
    }

    static func couldNotOpen(_ app: String) -> String {
        String(localized: "\(app) couldn’t be opened.", comment: "Add an App window, warning under the step “Choose the app”; %@ is the app")
    }

    static var chooseApp: String {
        String(localized: "Choose an App…", comment: "Add an App window: button under the step “Choose the app” that opens the window listing the apps")
    }

    static var chooserTitle: String {
        String(localized: "Choose an App", comment: "Title of the window that lists the apps Add an App can check")
    }

    static var chooserDescription: String {
        String(localized: "Choose the app that plays your music, podcasts or videos. Other App… finds one that isn’t listed.",
               comment: "The window that lists the apps Add an App can check, at its top; “Other App…” is its button")
    }

    static var otherApp: String {
        String(localized: "Other App…", comment: "Button in the window that lists the apps Add an App can check: picks an app in the Finder's open panel")
    }

    static var choose: String {
        String(localized: "Choose", comment: "The main button of the window that lists the apps Add an App can check")
    }

    static func otherAppProblem(_ problem: OtherAppProblem) -> String {
        switch problem {
        case .notAnApp:
            String(localized: "That isn’t an app AutoHush can check.", comment: "The window that lists the apps Add an App can check, after Other App… picked something else than an app")
        case .supported(let name):
            String(localized: "AutoHush supports \(name) already: choose it among the media players.",
                   comment: "The window that lists the apps Add an App can check, after Other App… picked a supported player; %@ is it")
        case .autoHush:
            String(localized: "That’s AutoHush itself.", comment: "The window that lists the apps Add an App can check, after Other App… picked AutoHush")
        }
    }

    /// Under a Chromium browser's web app in the list of apps.
    static func browserWebApp(_ browser: String) -> String {
        String(localized: "\(browser) web app", comment: "The window that lists the apps Add an App can check, under a web app made by Chrome or another Chromium browser (its icon carries the browser's): %@ is the browser, e.g. Google Chrome")
    }

    static var nowPlayingSection: String {
        String(localized: "In Now Playing", comment: "Add an App window: over the apps in macOS's Now Playing list, in the list of apps to choose")
    }

    static var otherAppsSection: String {
        String(localized: "Other Apps That Can Play", comment: "Add an App window: over the other apps that can play, in the list of apps to choose")
    }

    static var playingLabel: String { PlaybackState.playingLine }

    static var lookingForApps: String {
        String(localized: "Looking for apps that can play…", comment: "Add an App window, while it reads which apps can play")
    }

    static var noApps: String {
        String(localized: "No other app that can play was found.", comment: "Add an App window, instead of the list of apps when there's none to check")
    }

    // MARK: Step 2: permissions

    static var allowTitle: String {
        String(localized: "Allow what the check needs", comment: "Add an App window: the step that asks for the permissions the check needs")
    }

    static var allowNote: String {
        String(localized: "Only what that app needs, at once: Accessibility, Audio Recording, and Automation if it’s scriptable.",
               comment: "Add an App window, under the step “Allow what the check needs” before the app is chosen")
    }

    static func notScriptable(_ app: String) -> String {
        String(localized: "\(app) can’t be scripted, so Automation isn’t asked for.",
               comment: "Add an App window, under the step “Allow what the check needs”; %@ is the app")
    }

    static var accessibilityChanged: String {
        String(localized: "Accessibility changed while AutoHush was open. Reopen AutoHush to go on.",
               comment: "Add an App window, warning under the step “Allow what the check needs” when the check found Accessibility missing while AutoHush still sees it allowed (macOS tells AutoHush of the change only once it reopens); a Reopen AutoHush button follows")
    }

    static var neededInCheck: String {
        String(localized: "The check needs Accessibility allowed.",
               comment: "Add an App window, warning under the step “Allow what the check needs” when the check found Accessibility missing")
    }

    static var neededBadge: String {
        String(localized: "Needed", comment: "Add an App window: badge after a permission the check can't go without (Accessibility)")
    }

    static var optionalLabel: String {
        String(localized: "Optional", comment: "Add an App window: after a permission the check can go without, checking less")
    }

    static func accessibilityNeeded(_ app: String) -> String {
        String(localized: "The check needs Accessibility to read \(app)’s menus and page, use the Now Playing panel and move its window.",
               comment: "Add an App window, warning under the permissions while Accessibility isn't allowed; %@ is the app")
    }

    /// What the check does without the permissions in `missing` (Audio
    /// Recording, Automation), in one text (sentences joined in code read
    /// wrong in Chinese and Japanese); its Allow buttons and Continue say
    /// the rest.
    /// Without Audio Recording the Mac's sound is muted instead of the app's
    /// (`macMuted`), unless its output has no mute control.
    static func withoutWarning(_ missing: [CheckPermission], app: String, macMuted: Bool = false) -> String {
        switch (missing.contains(.audioRecording), missing.contains(.automation), macMuted) {
        case (true, true, true):
            String(localized: "Without Audio Recording, the Mac is muted during the check, and other signs tell whether \(app) plays. Without Automation, AppleScript, the surest way, isn’t tried.",
                   comment: "Add an App window, warning above Continue while neither Audio Recording nor Automation is allowed (the whole Mac's sound is muted during the check instead of the app's); %@ is the app")
        case (true, false, true):
            String(localized: "Without Audio Recording, the Mac is muted during the check, and other signs tell whether \(app) plays.",
                   comment: "Add an App window, warning above Continue while Audio Recording isn't allowed (the whole Mac's sound is muted during the check instead of the app's); %@ is the app")
        case (true, true, false):
            String(localized: "Without Audio Recording, you’ll hear \(app) during the check, and other signs tell whether it plays. Without Automation, AppleScript, the surest way, isn’t tried.",
                   comment: "Add an App window, warning above Continue while neither Audio Recording nor Automation is allowed (the app isn't muted during the check); %@ is the app")
        case (true, false, false):
            String(localized: "Without Audio Recording, you’ll hear \(app) during the check, and other signs tell whether it plays.",
                   comment: "Add an App window, warning above Continue while Audio Recording isn't allowed (the app isn't muted during the check); %@ is the app")
        case (false, true, _):
            String(localized: "Without Automation, AppleScript, the surest way to pause and play \(app), isn’t tried.",
                   comment: "Add an App window, warning above Continue while Automation for the app isn't allowed; %@ is the app")
        case (false, false, _):
            ""
        }
    }

    static var accessibilityTitle: String {
        String(localized: "Accessibility", comment: "Add an App window: the Accessibility permission (macOS's name for it)")
    }

    static func accessibilityUse(_ app: String) -> String {
        String(localized: "Reads \(app)’s menus and page, moves its window, and blocks the mouse and keyboard.",
               comment: "Add an App window, under “Accessibility”: what the check uses it for; %@ is the app")
    }

    static func audioUse(_ app: String) -> String {
        String(localized: "Hears whether \(app) plays, and mutes it.",
               comment: "Add an App window, under “Audio Recording”: what the check uses it for; %@ is the app")
    }

    static var automationUse: String {
        String(localized: "Pauses and plays it by AppleScript.",
               comment: "Add an App window, under “Automation”: what the check uses it for")
    }

    /// The Allow step once done: what's allowed, and what the check goes
    /// without.
    static func allowedSummary(_ permissions: CheckPermissions, antiDot: Bool) -> String {
        var allowed = [accessibilityTitle]
        var without: [String] = []
        if permissions.audio == .allowed, !antiDot { allowed.append(PermissionText.audioTitle) } else if !antiDot { without.append(PermissionText.audioTitle) }
        // With the app closed (a kept check reopened), macOS can't tell:
        // Automation isn't said either way.
        if let automation = permissions.automation, automation != .playerNotRunning {
            if automation == .allowed { allowed.append(automationTitle) } else { without.append(automationTitle) }
        }
        let allowedList = allowed.formatted(.list(type: .and))
        guard !without.isEmpty else {
            return String(localized: "\(allowedList) allowed", comment: "Add an App window, under the step “Allow what the check needs” once done; %@ lists the permissions, e.g. “Accessibility and Audio Recording”")
        }
        return String(localized: "\(allowedList) allowed; the check goes on without \(without.formatted(.list(type: .and)))",
                      comment: "Add an App window, under the step “Allow what the check needs” once done without some; the first %@ lists the permissions allowed, the second those it goes without, e.g. “Automation”")
    }

    /// macOS's name for the Automation permission, as the Allow step's row.
    static var automationTitle: String {
        String(localized: "Automation", comment: "Add an App window, in the list of permissions allowed: macOS's Automation permission")
    }

    /// The Allow step's button for one permission, as VoiceOver reads it:
    /// "Allow Accessibility…".
    static func allowLabel(_ permission: String) -> String {
        String(localized: "Allow \(permission)…", comment: "VoiceOver label of the Allow… button beside a permission in the Add an App window; %@ is the permission, e.g. Accessibility")
    }

    // MARK: Step 3: reopening

    static var reopenPending: String {
        String(localized: "It was opened without the option its page needs to be pressed while covered or on another desktop. AutoHush asks before reopening it.",
               comment: "Add an App window, under the step “Reopen %@” before it's the one to do")
    }

    static func reopening(_ app: String) -> String {
        String(localized: "Reopening \(app)…", comment: "Add an App window, under the step “Reopen %@” while it reopens; %@ is the app")
    }

    static var reopened: String {
        String(localized: "Reopened with its page’s option", comment: "Add an App window, under the step “Reopen %@” once done")
    }

    static var notReopened: String {
        String(localized: "Not reopened: its page may not take presses while it’s covered or on another desktop",
               comment: "Add an App window, under the step “Reopen %@” once skipped")
    }

    static func didNotQuit(_ app: String) -> String {
        String(localized: "\(app) didn’t quit (it may be asking something). Quit it yourself, then try again.",
               comment: "Add an App window, warning under the step “Reopen %@”; %@ is the app")
    }

    static var skip: String {
        String(localized: "Skip", comment: "Add an App window: button under the step “Reopen %@” that goes on without reopening the app")
    }

    // MARK: - When things go wrong, and the steps for VoiceOver

    static func appNotFound(_ app: String) -> String {
        String(localized: "\(app) quit and can’t be found. Choose another app.", comment: "Add an App window, warning under the step “Play something” when the app being checked quit and is no longer where it was chosen (moved or deleted); a Change… button follows; %@ is the app")
    }

    static func appQuit(_ app: String) -> String {
        String(localized: "\(app) quit. Open it again to go on.", comment: "Add an App window, warning under the step being done when the app being checked quit; %@ is the app")
    }

    /// Why a check couldn't finish, when AutoHush can tell.
    static func checkFailed(_ reason: PlayerCheckEnd.Reason?, app: String) -> String {
        switch reason {
        case .appQuit?:
            String(localized: "The check couldn’t finish: \(app) quit.", comment: "Add an App window, under the check's step when the app quit during the check; %@ is the app")
        case .appNotFound?:
            String(localized: "The check couldn’t finish: \(app) couldn’t be found.", comment: "Add an App window, under the check's step when the app couldn't be found; %@ is the app")
        case .other?, nil:
            String(localized: "The check couldn’t finish. Its log says why.", comment: "Add an App window, under the check's step when it ended without a result, for another reason (a Show Log button follows)")
        }
    }

    static var showLog: String {
        String(localized: "Show Log…", comment: "Add an App window: button that shows the check's log (in Console) after a check couldn't finish")
    }

    static var helperMissing: String {
        String(localized: "This copy of AutoHush can’t check apps: the part that runs the check is missing. Install AutoHush again.",
               comment: "Add an App window, instead of its steps, when the app's check helper is missing from AutoHush.app")
    }

    /// While the last check still puts things back.
    static var lastCheckEnding: String {
        String(localized: "The last check is putting things back first…", comment: "Add an App window, under the check's step, while a check that was stopped still puts windows and sound back; the new one starts after")
    }

    /// Audio Recording allowed in System Settings before the check:
    /// macOS applies it once AutoHush reopens (nothing found to keep yet).
    static var audioAllowedAwaitsReopen: String {
        String(localized: "Allowed in System Settings: it works once AutoHush reopens.",
               comment: "Add an App window, under Audio Recording before the check, after the user allowed it in System Settings: macOS applies it only from AutoHush's next launch; a Reopen AutoHush button follows")
    }

    /// Audio Recording allowed in System Settings after the check (above
    /// Mute It Instead): macOS applies it once AutoHush reopens.
    static var audioAfterReopen: String {
        String(localized: "Allowed in System Settings: it works once AutoHush reopens. What the check found is kept.",
               comment: "Add an App window, above Mute It Instead once the check is done, after the user allowed Audio Recording in System Settings: macOS applies it only from AutoHush's next launch; a Reopen AutoHush button follows")
    }

    /// A numbered step, as VoiceOver reads its title: "Step 2 of 6, …".
    static func stepLabel(_ number: Int, of count: Int, title: String) -> String {
        String(localized: "Step \(number) of \(count), \(title)", comment: "VoiceOver label of a numbered step's title in the Add an App window; the first %lld is its number, the second how many steps there are; %@ is its title")
    }
}
