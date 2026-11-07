import AppKit

/// The logs window's columns: the level's mark, when, the area and the
/// message. Each is as wide as its title, in the user's language, or its
/// widest entry, so the titles above the card line up with the rows.
@MainActor
struct LogColumns {
    static let spacing: CGFloat = 12
    /// The card's padding, which the titles are in line with.
    static var cardInset: CGFloat {
        if #available(macOS 26, *) { 14 } else { 12 }
    }
    static let shared = LogColumns()

    let level: CGFloat
    let time: CGFloat
    let area: CGFloat

    private init() {
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        let title = NSFont.systemFont(ofSize: 11, weight: .semibold)
        // The longest time: a two-digit day and hour, and the Mac's offset
        // from UTC in summer and in winter.
        let now = Date()
        let times = [now, now.addingTimeInterval(182 * 24 * 60 * 60)].map {
            "00/00/0000 00:00:00 " + LogsModel.utcOffset(seconds: TimeZone.current.secondsFromGMT(for: $0))
        }
        level = max(14, width(Self.levelTitle, title))
        time = max(times.map { width($0, .monospacedDigitSystemFont(ofSize: 14, weight: .regular)) }.max() ?? 0,
                   width(Self.timeTitle, title))
        area = max(LogsModel.areas.map { width($0, .systemFont(ofSize: 11)) }.max() ?? 0, width(Self.areaTitle, title))
    }

    static var levelTitle: String {
        String(localized: "Level", comment: "The logs window: title of the column that marks each entry's level (a problem, a notice, information)")
    }

    static var timeTitle: String {
        String(localized: "Time", comment: "The logs window: title of the column with when each entry was logged (its date, time and offset from UTC)")
    }

    static var areaTitle: String {
        String(localized: "Area", comment: "The logs window: title of the column with the part of AutoHush that logged each entry (Player, Detection, Updates…)")
    }

    static var messageTitle: String {
        String(localized: "Message", comment: "The logs window: title of the column with what each entry says")
    }
}
