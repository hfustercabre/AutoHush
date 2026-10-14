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
            case .apps: AppsSettingsView(model: model)
            case .detection: DetectionSettingsView(model: model)
            case .fades: FadesSettingsView(model: model)
            case .diagnostics: DiagnosticsSettingsView(model: model)
            case .updates: UpdatesSettingsView(model: model)
            case .about: AboutSettingsView(model: model)
            }
        }
        .font(.appBody)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A Settings page's cards, as wide as the page and scrolling when the
/// window is shorter than they are.
struct SettingsPageScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
