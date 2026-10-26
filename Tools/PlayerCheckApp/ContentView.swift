import AppKit
import SwiftUI

struct ContentView: View {
    let checker: Checker
    @State private var selection: InstalledApp.ID?
    @State private var search = ""

    private var shown: [InstalledApp] {
        let apps = checker.nowPlayingApps
        return search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                let listed = shown.filter { checker.client(of: $0) != nil }
                if !listed.isEmpty {
                    Section("In Now Playing Now") {
                        ForEach(listed) { app in
                            AppRow(app: app, isRunning: checker.isRunning(app), client: checker.client(of: app),
                                   isChecked: checker.finished[app.id] != nil).tag(app.id)
                        }
                    }
                }
                ForEach(InstalledApp.Root.allCases, id: \.self) { root in
                    let apps = shown.filter { $0.root == root && checker.client(of: $0) == nil }
                    if !apps.isEmpty {
                        Section(root.title) {
                            ForEach(apps) { app in
                                AppRow(app: app, isRunning: checker.isRunning(app), client: nil,
                                       isChecked: checker.finished[app.id] != nil).tag(app.id)
                            }
                        }
                    }
                }
            }
            .overlay {
                if checker.isScanning && checker.apps.isEmpty {
                    ProgressView("Looking in the Applications folders…")
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search apps")
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    Text("\(checker.nowPlayingApps.count) of \(checker.apps.count) apps can be in Now Playing")
                    if checker.isReadingClients {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Reading macOS's Now Playing list…")
                        }
                    } else if let problem = checker.clientsProblem {
                        Text(problem).multilineTextAlignment(.center)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(8)
                .background(.bar)
            }
        } detail: {
            if let app = checker.apps.first(where: { $0.id == selection }) {
                AppDetail(app: app, checker: checker)
                    .id(app.id)
            } else {
                ContentUnavailableView("Choose an App", systemImage: "music.note.list",
                                       description: Text("Player Check finds out whether AutoHush could pause and play it, and how."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button { checker.scan() } label: { Label("Look Again", systemImage: "arrow.clockwise") }
                    .disabled(checker.isScanning)
                    .help("Look in the Applications folders and macOS's Now Playing list again")
            }
        }
        .onAppear { checker.scan() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            checker.refreshRunning()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            checker.refreshRunning()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checker.refreshRunning()
        }
        .frame(minWidth: 820, minHeight: 520)
    }
}
