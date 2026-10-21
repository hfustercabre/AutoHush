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
            case .soundSources: SoundSourcesSettingsView(model: model)
            case .detection: DetectionSettingsView(model: model)
            case .fades: FadesSettingsView(model: model)
            case .calls: CallsSettingsView(model: model)
            case .advanced: AdvancedSettingsView(model: model)
            case .diagnostics: DiagnosticsSettingsView(model: model)
            case .updates: UpdatesSettingsView(model: model)
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
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?

    var body: some View {
        ScrollViewReader { scroller in
            Form { content }
                .formStyle(.grouped)
                .environment(\.cardsAreFormSections, true)
                // The arrow keys' highlight scrolls into view.
                .onChange(of: keyboard?.revealed) { _, revealed in
                    if let revealed { withAnimation(.easeOut(duration: 0.15)) { scroller.scrollTo(revealed) } }
                }
        }
    }
}
