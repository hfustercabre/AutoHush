import AppKit
import SwiftUI

/// The page the sidebar points to.
struct SettingsPageView: View {
    let model: SettingsModel
    let navigation: SettingsNavigation

    var body: some View {
        Group {
            switch navigation.page {
            case .general: GeneralSettingsView(model: model)
            case .mediaPlayer: MediaPlayerSettingsView(model: model)
            case .soundSources: SoundSourcesSettingsView(model: model)
            case .behavior: BehaviorSettingsView(model: model)
            case .fineTuning: FineTuningSettingsView(model: model)
            case .diagnostics: DiagnosticsSettingsView(model: model)
            case .about: AboutSettingsView(model: model)
            }
        }
        // No font of its own: macOS's form sets its rows' and titles'.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A Settings page's content as macOS's grouped form, as System Settings'
/// pages are (the user, 2026-10-17): its `Card`s are the form's sections,
/// drawn and spaced by macOS, and it scrolls by itself.
struct SettingsPageScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { scroller in
            Form { content }
                .formStyle(.grouped)
                .environment(\.cardsAreFormSections, true)
                // The arrow keys' highlight scrolls into view.
                .revealsKeyHighlight(with: scroller)
        }
    }
}
