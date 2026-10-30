import Foundation

/// The checks kept between launches.
extension Checker {
    private struct SavedReport: Codable {
        let lines: [String]
        let date: Date
        /// The checks' kind: 4 from when each way is tested in every window
        /// state (✓ means all of them). Older ones are dropped: their ✓ meant
        /// one state, wherever the window happened to be.
        var version: Int? = SavedReport.currentVersion
        static let currentVersion = 4
    }
    private static let savedReports = URL.applicationSupportDirectory.appending(path: "Player Check/reports.json")

    func loadReports() {
        guard let data = try? Data(contentsOf: Self.savedReports),
              let saved = try? JSONDecoder().decode([String: SavedReport].self, from: data) else { return }
        finished = saved.filter { $0.value.version == SavedReport.currentVersion }
            .mapValues { CheckReport(state: .finished, lines: $0.lines, date: $0.date) }
        reports = finished
    }

    func saveReports() {
        let saved = finished.mapValues { SavedReport(lines: $0.lines, date: $0.date) }
        try? FileManager.default.createDirectory(at: Self.savedReports.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(saved).write(to: Self.savedReports, options: .atomic)
    }
}
