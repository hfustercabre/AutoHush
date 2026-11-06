import AppKit
import SwiftUI

/// The page the sidebar points to.
struct SettingsPageView: View {
    let model: SettingsModel
    let navigation: SettingsNavigation
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?

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
        // Shown by a key's press, or VoiceOver's, its first control lights
        // up once it's drawn, VoiceOver's cursor with it (N8, the a11y
        // audit, 2026-11-06); once, whatever page shows next.
        .onChange(of: navigation.page) {
            if model.shownPageTakesHighlight { keyboard?.highlightFirstWhenReady() }
            model.shownPageTakesHighlight = false
        }
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
