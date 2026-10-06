import SwiftUI
import AutoHushKit

/// Settings → General, in cards like the menu's: launch at login, then Music
/// (auto-pause, the player), Privacy (AntiDot mode) and Updates (checks,
/// what they lead to, Check Now), and a way to support AutoHush.
struct GeneralSettingsView: View {
    let model: SettingsModel
    /// The players' search is open, beside their pop-up.
    @State private var searchingPlayers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Card {
                SwitchRow(Text("Launch at login"), isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let error = model.launchAtLoginError {
                    NoteLabel(error)
                    Button("Open Login Items Settings…") { model.openLoginItemsSettings() }
                        .buttonStyle(.chip)
                }
            }

            SectionHeading(Text("Music"))
            Card {
                SwitchRow(
                    Text("Auto-Pause Music"),
                    subtitle: Text("Choose which apps pause your music in the Apps tab."),
                    isOn: Binding(get: { model.isAutoPauseOn }, set: { model.setAutoPause($0) })
                )
                if let note = model.autoPauseNote {
                    Text(note).captionStyle()
                }
                CardDivider()
                HStack {
                    RowTitle(Text("Music player"), subtitle: Text("AutoHush pauses and resumes this app."))
                    Spacer(minLength: 8)
                    PlayerPopUp(options: model.playerOptions.offered, selection: model.chosenPlayerID,
                                onSelect: { model.chooseMusicPlayer($0) }, onAddWebApp: { model.addWebApp() })
                    if model.playerOptions.isSearchable { playerSearchButton }
                    IconChipButton(symbol: "plus", label: Text(verbatim: PlayerOption.addWebAppTitle)) { model.addWebApp() }
                }
                if model.playerOptions.noneInstalled {
                    NoteLabel(PlayerOption.noneInstalledWarning)
                }
                // Until AutoHush has learned the chosen web app's controls.
                if let name = model.chosenPlayerName, let hasPlayed = model.learningHasPlayed {
                    CardDivider()
                    LearningSummary(name: name, hasPlayed: hasPlayed)
                }
            }

            SectionHeading(Text("Privacy"))
            Card {
                SwitchRow(
                    Text("AntiDot mode"),
                    subtitle: Text("Hides the purple recording indicator. Detection is less precise.",
                                   comment: "Settings, under AntiDot mode"),
                    isOn: Binding(get: { model.isAntiDotMode }, set: { model.setAntiDotMode($0) })
                )
                if model.isAntiDotMode {
                    CardDivider()
                    SectionLabel(Text("Detect playing apps by"))
                    ChoiceChips(
                        options: [DetectionMethod.playbackSignals, .openStreams].map { .init(title: $0.title, value: $0) },
                        selection: model.detectionMethod,
                        onSelect: { model.setDetectionMethod($0) }
                    )
                    Text(model.detectionMethod.summary).captionStyle()
                }
            }

            SectionHeading(Text("Updates"))
            Card {
                SwitchRow(Text("Check for updates automatically"), isOn: Binding(
                    get: { model.checksForUpdatesAutomatically },
                    set: { model.setChecksForUpdates($0) }
                ))
                // What checks lead to only matters while they run.
                if model.checksForUpdatesAutomatically {
                    CardDivider()
                    SectionLabel(Text("When an update is found"))
                    ChoiceChips(
                        options: [AutomaticUpdates.notify, .download, .install].map {
                            .init(title: $0.title, value: $0, isAvailable: model.isAvailable($0))
                        },
                        // A copy that can't install itself can only notify.
                        selection: model.updateInstallNote == nil ? model.automaticUpdates : .notify,
                        onSelect: { model.setAutomaticUpdates($0) },
                        onUnavailableClick: { model.flashNotificationsNote() }
                    )
                    .disabled(model.updateInstallNote != nil)
                    Text(model.updateInstallNote ?? model.automaticUpdates.explanation).captionStyle()
                }
                // Shown even with checks off: AutoHush turns them off when notifications go off.
                if model.notificationsOff {
                    // Blinks bright after a click on a choice that needs notifications.
                    Text("Notifications are off for AutoHush, so it can't tell you about updates.")
                        .font(.appCaption)
                        .foregroundStyle(model.notificationsNoteIsLit ? AnyShapeStyle(.primary) : AnyShapeStyle(.appSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Notifications Settings…") { model.openNotificationSettings() }
                        .buttonStyle(.chip)
                }
                CardDivider()
                HStack {
                    RowTitle(Text(model.updateTitle), subtitle: model.lastCheckedNote().map { Text($0) })
                    Spacer(minLength: 8)
                    Button("Check Now") { model.checkForUpdates() }
                        .buttonStyle(.chip)
                }
            }

            SupportLine()
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        .padding(16)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// From `PlayerOption.searchThreshold` players on: a magnifier that opens
    /// a search over them, where a click on one chooses it.
    private var playerSearchButton: some View {
        IconChipButton(symbol: "magnifyingglass",
                       label: Text("Search by name", comment: "The magnifier that opens a search")) {
            searchingPlayers = true
        }
        .popover(isPresented: $searchingPlayers, arrowEdge: .bottom) {
            PlayerSearchPopover(options: model.playerOptions.offered, chosen: model.chosenPlayerID) {
                model.chooseMusicPlayer($0)
                searchingPlayers = false
            }
        }
    }
}

/// The detection choices as Settings and Diagnostics describe them.
extension DetectionMethod {
    var title: String {
        switch self {
        case .audioLevels:
            return String(localized: "Measure audio levels", comment: "Settings: a way to detect playing apps")
        case .playbackSignals:
            return String(localized: "What apps tell macOS", comment: "Settings, AntiDot mode: a way to detect playing apps")
        case .openStreams:
            return String(localized: "Open audio streams only",
                          comment: "Settings, AntiDot mode: a way to detect playing apps")
        }
    }

    var summary: String {
        switch self {
        case .audioLevels:
            return String(localized: "Most accurate: a paused video stops counting as soon as it goes silent. macOS shows its purple recording indicator while AutoHush measures.")
        case .playbackSignals:
            return String(localized: "An app counts as playing while it tells macOS it's playing, and as paused once it stops, even with its audio still open. Apps that never tell macOS count while their audio is open. Sound without video must last at least 3 seconds before your music pauses, so notification sounds don't interrupt it.")
        case .openStreams:
            return String(localized: "Any app with its audio open counts as playing, even when paused.")
        }
    }
}

/// Each update choice as Settings and Diagnostics show it.
extension AutomaticUpdates {
    var title: String {
        switch self {
        case .notify:
            return String(localized: "Notify me", comment: "Settings: an update choice")
        case .download:
            return String(localized: "Download it and notify me", comment: "Settings: an update choice")
        case .install:
            return String(localized: "Install it automatically", comment: "Settings: an update choice")
        }
    }

    /// What the choice means, under the choices.
    var explanation: String {
        switch self {
        case .notify:
            return String(localized: "AutoHush lets you know. Install the update from its menu whenever you like.",
                          comment: "Settings, under the update choice Notify me")
        case .download:
            return String(localized: "AutoHush downloads it and lets you know. It keeps the download for 7 days.",
                          comment: "Settings, under the update choice Download it and notify me")
        case .install:
            return String(localized: "AutoHush installs it when it isn't holding your music paused, and lets you know afterwards.",
                          comment: "Settings, under the update choice Install it automatically")
        }
    }
}
