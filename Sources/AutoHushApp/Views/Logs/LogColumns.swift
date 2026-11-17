import AppKit
import Observation

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
    /// As measured for the Mac's time zone now: measured again when it
    /// changes (travel), so the times aren't cut (K3-6 of 11-11).
    static var shared: LogColumns { measured.columns }
    private static let measured = Measured()

    /// The columns, measured again each time the time zone changes; the
    /// rows that read them are drawn again then.
    @MainActor @Observable final class Measured {
        private(set) var columns: LogColumns
        @ObservationIgnored private let timeZone: () -> TimeZone

        /// The shared one watches as long as the app runs; a test's, its own `center`.
        init(timeZone: @escaping () -> TimeZone = { .current }, center: NotificationCenter = .default) {
            self.timeZone = timeZone
            columns = LogColumns(timeZone: timeZone())
            _ = center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.columns = LogColumns(timeZone: self.timeZone())
                }
            }
        }
    }

    let level: CGFloat
    let time: CGFloat
    let area: CGFloat

    init(timeZone: TimeZone) {
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        let title = NSFont.systemFont(ofSize: 11, weight: .semibold)
        // The longest time: a two-digit day and hour, and the Mac's offset
        // from UTC in summer and in winter.
        let now = Date()
        let times = [now, now.addingTimeInterval(182 * 24 * 60 * 60)].map {
            "00/00/0000 00:00:00 " + LogsModel.utcOffset(seconds: timeZone.secondsFromGMT(for: $0))
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
