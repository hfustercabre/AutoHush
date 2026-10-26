import AppKit
import SwiftUI

/// The window the first step of Add an App opens (the user, 2026-10-15:
/// the list can be long): every app found that can play, those in macOS's
/// Now Playing list first, with a search; Other App… picks one on the disk.
/// Choose (Return, or a double click) goes on with the one selected, or
/// with the only one the search left; ↑ and ↓ in the search move the
/// selection.
struct AppChooserView: View {
    @Bindable var model: AddAppModel
    let otherApp: () -> Void
    let close: () -> Void

    /// The window's width, Add an App's, which its bottom bar's buttons fit
    /// in every language.
    static let width = AddAppView.width

    var body: some View {
        WindowPage(icon: NSApp.applicationIconImage, description: Text(verbatim: AddAppText.chooserDescription), width: Self.width) {
            SearchField(text: $model.search, focusesOnAppear: true, onSubmit: chooseSelected, onMove: moveSelection)
                .padding(.top, 8)
            Card { list }
            if let problem = model.otherAppProblem { NoteLabel(AddAppText.otherAppProblem(problem)) }
        } bar: {
            Button(action: otherApp) { Text(verbatim: AddAppText.otherApp) }
                .buttonStyle(.chip)
            Spacer()
            Button(action: close) { Text(verbatim: ButtonText.cancel) }
                .buttonStyle(.chip)
                .keyboardShortcut(.cancelAction)
            MainButton(AddAppText.choose, action: chooseSelected)
                .disabled(selected == nil)
        }
        // VoiceOver hears why a pick on the disk can't be checked.
        .onChange(of: model.otherAppProblem) { _, problem in
            if let problem { AccessibilityNotification.Announcement(AddAppText.otherAppProblem(problem)).post() }
        }
    }

    /// The app selected among those shown, else the only one shown.
    private var selected: CheckableApp? {
        let shown = model.shownAppsInOrder
        return shown.first { $0.id == model.selectedID } ?? (shown.count == 1 ? shown.first : nil)
    }

    /// ↑ or ↓: the one before or after the selected among those shown.
    private func moveSelection(_ step: Int) {
        let shown = model.shownAppsInOrder
        guard !shown.isEmpty else { return }
        let index = shown.firstIndex { $0.id == model.selectedID }.map { $0 + step } ?? (step > 0 ? 0 : shown.count - 1)
        model.selectedID = shown[min(max(index, 0), shown.count - 1)].id
    }

    private func chooseSelected() {
        guard let selected else { return }
        model.choose(selected)
    }

    @ViewBuilder private var list: some View {
        if model.isLoadingApps && model.apps.isEmpty {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(verbatim: AddAppText.lookingForApps).captionStyle()
            }
            .frame(maxWidth: .infinity, minHeight: 80)
        } else if model.apps.isEmpty {
            Text(verbatim: AddAppText.noApps).captionStyle().frame(maxWidth: .infinity, minHeight: 80)
        } else {
            let shown = model.shownApps
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if !shown.inNowPlaying.isEmpty { section(AddAppText.nowPlayingSection, shown.inNowPlaying) }
                        if !shown.others.isEmpty {
                            section(AddAppText.otherAppsSection, shown.others).padding(.top, shown.inNowPlaying.isEmpty ? 0 : 6)
                        }
                        if shown.inNowPlaying.isEmpty && shown.others.isEmpty {
                            Text(verbatim: PlayerOption.noMatchNote(model.search)).captionStyle()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 320)
                // ↑ and ↓ keep the selected app in view.
                .onChange(of: model.selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func section(_ title: String, _ apps: [CheckableApp]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).font(.appCaption).foregroundStyle(.appSecondary).accessibilityAddTraits(.isHeader)
            ForEach(apps) { app in
                let isSelected = model.selectedID == app.id
                HStack(spacing: 8) {
                    Image(nsImage: AppIcon.appImage(bundlePath: app.url.path, size: 20))
                        .resizable().frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: app.name)
                        let lines = [app.browserName.map(AddAppText.browserWebApp), app.nowPlaying == true ? AddAppText.playingLabel : nil]
                            .compactMap { $0 }
                        if !lines.isEmpty {
                            Text(verbatim: lines.joined(separator: " · ")).font(.appCaption).foregroundStyle(.appSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .id(app.id)
                .background {
                    if isSelected { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.selectedTileFill) }
                }
                .contentShape(Rectangle())
                // Selected at the first click, not after the double click's wait.
                .onTapGesture(count: 2) { model.selectedID = app.id; chooseSelected() }
                .simultaneousGesture(TapGesture().onEnded { model.selectedID = app.id })
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { model.selectedID = app.id }
            }
        }
    }
}
