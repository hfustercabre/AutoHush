import CoreGraphics

/// Settings → About's icon fitted to the page (`AboutSettingsView`): the
/// icon's side, and the name with it, from the page's size and the
/// content's and the name's as measured; the icon beside the name when
/// even `leastIconSize` leaves the page too tall (M5, 2026-10-31). One
/// value, so the view keeps one state (the 1.2.9 review, 2026-11-01).
struct AboutFit {
    /// The icon's least and largest sides: it resizes a little, at most to
    /// F2's 128 pt (the user, 2026-10-31: "making it resize but only a
    /// little? At most as the F2"), and shrinks so the copyright line fits
    /// the window's minimum size in the page's tallest case (no automatic
    /// checks, a release candidate offered, Restore Defaults).
    static let leastIconSize: CGFloat = 64
    static let largestIconSize: CGFloat = 128
    /// The icon's side the first opening of a run starts from.
    static let openingIconSize: CGFloat = 96
    /// The least a fit grows the icon by (`fittedIconSize`).
    static let leastGrowth: CGFloat = 3
    /// The page's margin on every side, in the content's height as measured.
    static let pageMargin: CGFloat = 20

    /// The icon sides the content and the name were last measured beside.
    struct MeasuredBeside {
        var content: CGFloat = 0
        var name: CGFloat = 0
    }

    /// The icon's side; the name grows and shrinks with it.
    private(set) var iconSize = AboutFit.openingIconSize
    /// The page's size, its content's height (padding included) and the
    /// name's size as last measured, and the icon's side each of the last two
    /// was measured beside: a fit waits until the content is of the icon
    /// shown and the name was measured once, as the name is measured after
    /// the content (it stayed 96 pt until the window was resized,
    /// 2026-10-31); the name's size is then scaled to the icon (`nameSize`).
    private(set) var pageSize: CGSize = .zero
    private(set) var contentHeight: CGFloat = 0
    private(set) var nameSize: CGSize = .zero
    private(set) var measuredBeside = MeasuredBeside()
    /// The icon beside the name and the version: the page is too short for
    /// them on lines of their own even at `leastIconSize` (M5, the user's
    /// pick, 2026-10-31). Then the content's height as last measured, and
    /// how much taller the stacked header at `leastIconSize` made it,
    /// measured as it changed over.
    private(set) var isCompact = false
    private(set) var compactHeight: CGFloat = 0
    private(set) var stackedAtLeast: CGFloat = 0
    private(set) var stackedExtra: CGFloat = 0

    /// The first opening of a run: nothing measured, the icon at
    /// `openingIconSize`.
    init() {}

    /// The next opening, from where `last` left the icon and the header, so
    /// the icon doesn't jump as the page opens (I1, the user, 2026-11-01):
    /// nothing measured, as the page and its content may have changed since.
    /// The compact header only with its way back measured (`stackedExtra`),
    /// else the stacked one at the icon's last side.
    init(resuming last: AboutFit?) {
        guard let last else { return }
        iconSize = last.iconSize
        if last.isCompact, last.stackedExtra > 0 {
            isCompact = true
            stackedExtra = last.stackedExtra
        }
    }

    /// The page's size changed: fit to it.
    mutating func pageChanged(to size: CGSize) {
        pageSize = size
        fit()
    }

    /// The content's height (padding included) was measured beside the
    /// header shown.
    mutating func contentMeasured(height: CGFloat) {
        if isCompact {
            compactHeight = height
            if stackedExtra == 0 { stackedExtra = stackedAtLeast - height }
        } else {
            contentHeight = height
            measuredBeside.content = iconSize
        }
        fit()
    }

    /// The name's size was measured beside the icon shown.
    mutating func nameMeasured(_ size: CGSize) {
        nameSize = size
        measuredBeside.name = iconSize
        fit()
    }

    /// Fits the icon, and the name with it, to the page's room, once the
    /// content is measured beside the icon shown and the name once; puts
    /// the icon beside the name when even `leastIconSize` doesn't fit, and
    /// back on its own line once it does.
    private mutating func fit() {
        if isCompact {
            guard compactHeight > 0, stackedExtra > 0 else { return }
            if Self.stackedFits(page: pageSize, compactContent: compactHeight, stackedExtra: stackedExtra) {
                isCompact = false
            }
            return
        }
        guard measuredBeside.content == iconSize, measuredBeside.name > 0 else { return }
        let name = Self.nameSize(nameSize, measuredBeside: measuredBeside.name, at: iconSize)
        let atLeast = Self.contentHeight(atIcon: Self.leastIconSize, current: iconSize, content: contentHeight, name: name)
        if pageSize.height > 0, atLeast > pageSize.height + 0.5 {
            stackedAtLeast = atLeast
            stackedExtra = 0
            iconSize = Self.leastIconSize
            isCompact = true
            return
        }
        let fitted = Self.fittedIconSize(current: iconSize, page: pageSize, content: contentHeight, name: name)
        if abs(fitted - iconSize) >= 1 { iconSize = fitted }
    }

    /// The name's size beside an icon of `side`, from one measured beside
    /// `measured`: its font follows the icon, and its size with it. A 1 pt
    /// step may leave the name's rounded size as it was, so it isn't
    /// measured again: the fit would have waited for good (on a 1x screen,
    /// the 1.2.9 review).
    static func nameSize(_ size: CGSize, measuredBeside measured: CGFloat, at side: CGFloat) -> CGSize {
        guard measured > 0 else { return size }
        return CGSize(width: size.width * side / measured, height: size.height * side / measured)
    }

    /// The content's height with the icon at `side`, from one measured
    /// beside `current`: the icon's and the name's heights follow it.
    static func contentHeight(atIcon side: CGFloat, current: CGFloat, content: CGFloat, name: CGSize) -> CGFloat {
        guard current > 0 else { return content }
        return content - (current - side) - name.height * (1 - side / current)
    }

    /// The stacked header fits again at `leastIconSize`, with 2 pt to spare
    /// so the two headers never take turns (the compact one went in at 0.5
    /// over).
    static func stackedFits(page: CGSize, compactContent: CGFloat, stackedExtra: CGFloat) -> Bool {
        page.height > 0 && compactContent + stackedExtra <= page.height - 2
    }

    /// The icon's side that makes the page as tall as `page` (its room
    /// shared by the icon and the name, whose height follows it), within
    /// `leastIconSize`…`largestIconSize`, the name kept on one line between
    /// the page's margins, grown only by `leastGrowth` or more while the
    /// room is tight. Nothing measured yet, the page's size included:
    /// `current`.
    static func fittedIconSize(current: CGFloat, page: CGSize, content: CGFloat, name: CGSize) -> CGFloat {
        guard current > 0, page.width > 0, page.height > 0, content > 0, name.width > 0, name.height > 0 else { return current }
        let fixed = content - current - name.height
        let byHeight = (page.height - fixed) / (1 + name.height / current)
        let byName = (page.width - 2 * pageMargin) * current / name.width
        let room = min(byHeight, byName)
        let fitted = max(leastIconSize, min(room, largestIconSize)).rounded(.down)
        // It shrinks at once but grows only by `leastGrowth` or more, unless
        // the room is that much larger: the name's line height steps with
        // its font, so 1 pt more can overflow again, and the two sizes took
        // turns for good (79 and 80 pt at the window's minimum size,
        // 2026-10-31).
        let tight = room < fitted + leastGrowth
        return tight && fitted > current && fitted < current + leastGrowth ? current : fitted
    }
}
