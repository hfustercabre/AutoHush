import AppKit
import SwiftUI

/// The window the first step of Add an App opens (the user, 2026-10-15:
/// the list can be long): every app found that can play, those in macOS's
/// Now Playing list first, with a search; Other App… picks one on the disk.
/// Choose (Return, or a double click) goes on with the one selected, or
/// with the only one the search left; ↑ and ↓ in the search move the
/// selection, which VoiceOver hears (N10, 2026-11-06).
struct AppChooserView: View {
    @Bindable var model: AddAppModel
    let otherApp: () -> Void
    let close: () -> Void
    /// The last note VoiceOver was told (`AddAppModel.otherAppNote`).
    @State private var noteAnnounced: OtherAppNote.ID?

    /// The window's width, Add an App's, which its bottom bar's buttons fit
    /// in every language.
    static let width = AddAppView.width

    var body: some View {
        WindowPage(icon: NSApp.applicationIconImage, description: Text(verbatim: AddAppText.chooserDescription), width: Self.width) {
            SearchField(text: $model.search, focusesOnAppear: true, results: searchResults, onSubmit: chooseSelected, onMove: moveSelection)
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
        // VoiceOver hears why a pick can't be checked: each time it's shown,
        // also when the window opens with it (the 1.3.1 review's WA-2, N-3).
        .onAppear(perform: announceProblem)
        .onChange(of: model.otherAppNote?.id) { _, _ in announceProblem() }
    }

    private func announceProblem() {
        guard let note = model.otherAppNote, note.id != noteAnnounced else { return }
        noteAnnounced = note.id
        // High priority, through AppKit: the window opening and its search
        // taking focus would cut SwiftUI's announcement off (the diff
        // review's finding 1, as step announcements, 2026-10-18).
        postStepAnnouncement(AddAppText.otherAppProblem(note.problem))
    }

    /// What the search found, for VoiceOver; nothing while the apps load.
    private var searchResults: SearchResults? {
        model.apps.isEmpty ? nil : SearchResults(count: model.shownAppsInOrder.count, noMatch: PlayerOption.noMatchNote(model.search))
    }

    /// The app selected among those shown, else the only one shown.
    private var selected: CheckableApp? {
        let shown = model.shownAppsInOrder
        return shown.first { $0.id == model.selectedID } ?? (shown.count == 1 ? shown.first : nil)
    }

    /// ↑ or ↓: the one before or after the selected among those shown. Its
    /// cursor still in the search, VoiceOver hears which, after what it's
    /// saying, as a search's results (N10, the a11y audit, 2026-11-06).
    private func moveSelection(_ step: Int) {
        guard let app = model.moveSelection(step) else { return }
        postAnnouncement(AddAppText.chooserSelection(app), priority: .low)
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
                        let lines = AddAppText.chooserLines(app)
                        if !lines.isEmpty {
                            Text(verbatim: lines.joined(separator: " · ")).font(.appCaption)
                                .foregroundStyle(isSelected ? AnyShapeStyle(.onSelection) : AnyShapeStyle(.appSecondary))
                        }
                    }
                    // Selected, white on the accent color, as macOS's lists (A1a).
                    .foregroundStyle(isSelected ? AnyShapeStyle(.onSelection) : AnyShapeStyle(.foreground))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .id(app.id)
                .background {
                    if isSelected { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.listSelectionFill) }
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
