import AutoHushKit
import PlayerCheckKit

/// What a look shows, for the log: its menu's and page's words only (`shown`).
extension Look {
    @MainActor var line: String {
        [menuTitle.map { "menu \(shown($0))" + (menuState == .stopped ? " (disabled)" : "") }, state.map { "state \($0.rawValue)" },
         reported.map { "reports \($0.lowercased())" },
         pageToggle.map { "page \(shown($0))" + (pageCurrent ? "" : " (out of sight: its word lags)") }, "sound \(sounding ? "on" : "off")",
         audible.map { $0 ? "heard" : "silent" },
         awake.map { awake in
             // A browser's web app: the browser's "Playing audio" assertions, counted (`pagesSay`).
             webAppBrowser == nil ? (awake ? "keeps the Mac awake" : "no keep-awake assertion")
                 : awake ? "its “Playing audio” held" : "no “Playing audio” of its own"
         }]
            .compactMap { $0 }.joined(separator: ", ")
    }
}
