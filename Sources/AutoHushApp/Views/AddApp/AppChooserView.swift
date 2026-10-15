import AppKit
import SwiftUI

/// The window the first step of Add an App opens (the user, 2026-10-15:
/// the list can be long): every app found that can play, those in macOS's
/// Now Playing list first, with a search; Other App… picks one on the disk.
/// Choose (Return, or a double click) goes on with the one selected.
struct AppChooserView: View {
    @Bindable var model: AddAppModel
    let otherApp: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                WindowHeader(icon: NSApp.applicationIconImage, description: Text(verbatim: AddAppText.chooserDescription))
                SearchField(text: $model.search, focusesOnAppear: true, onSubmit: chooseSelected)
                    .padding(.top, 8)
                Card { list }
                if let problem = model.otherAppProblem { NoteLabel(AddAppText.otherAppProblem(problem)) }
            }
            .windowMargins()
            BottomBar(margin: HostedWindowController.margin) {
                Button(action: otherApp) { Text(verbatim: AddAppText.otherApp) }
                    .buttonStyle(.chip)
                Spacer()
                Button(action: close) { Text(verbatim: AddAppText.cancel) }
                    .buttonStyle(.chip)
                    .keyboardShortcut(.cancelAction)
                Button(action: chooseSelected) {
                    Text(verbatim: AddAppText.choose).font(.appBody.weight(.semibold)).padding(.horizontal, 6)
                }
                .buttonStyle(ChipButtonStyle(filled: true, isSelected: true, padded: true))
                .keyboardShortcut(.defaultAction)
                .disabled(selected == nil)
            }
        }
        .frame(width: 460)
        .font(.appBody)
    }

    private var selected: CheckableApp? {
        let shown = model.shownApps
        return (shown.inNowPlaying + shown.others).first { $0.id == model.selectedID }
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
                .background {
                    if isSelected { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.selectedTileFill) }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.selectedID = app.id; chooseSelected() }
                .onTapGesture { model.selectedID = app.id }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { model.selectedID = app.id }
            }
        }
    }
}
