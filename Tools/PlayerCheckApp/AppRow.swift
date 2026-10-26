import AppKit
import SwiftUI

struct AppRow: View {
    let app: InstalledApp
    let isRunning: Bool
    let client: NowPlayingClient?
    let isChecked: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                let notes = [client?.summary, isChecked ? "checked" : nil, app.subfolder, app.nowPlayingReason]
                    .compactMap { $0 }
                if !notes.isEmpty {
                    Text(notes.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isRunning {
                Circle().fill(.green).frame(width: 7, height: 7).help("Running")
            }
        }
    }
}
