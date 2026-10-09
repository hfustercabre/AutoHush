import AppKit
import SwiftUI

/// A native pop-up of the music players, with their icons, a heading over
/// the Safari web apps, and "Add a Web App…" last, after the item that
/// learns the chosen web app's controls again (once learned). A player that isn't
/// installed is dimmed, marked "Not installed", and can't be chosen; a
/// suggested web app is marked so too, but picking it opens "Add a Web App".
/// While none is chosen, a placeholder asks for one. SwiftUI's menu picker
/// can't dim a single option.
struct PlayerPopUp: NSViewRepresentable {
    let options: [PlayerOption]
    /// The chosen player's bundle ID; `nil` while none is chosen.
    let selection: String?
    let onSelect: (String) -> Void
    var onAddWebApp: () -> Void = {}
    /// The chosen player's name, for the item that learns its controls
    /// again (with the name under it); `nil` hides it.
    var learnAgainName: String?
    var onLearnAgain: () -> Void = {}

    func makeNSView(context: Context) -> PlayerPopUpButton {
        PlayerPopUpButton()
    }

    func updateNSView(_ view: PlayerPopUpButton, context: Context) {
        view.update(options: options, selection: selection, learnAgainName: learnAgainName)
        view.onSelect = onSelect
        view.onAddWebApp = onAddWebApp
        view.onLearnAgain = onLearnAgain
    }

    /// As wide as its longest item, like a native pop-up, not the whole row.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PlayerPopUpButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

/// The pop-up button behind `PlayerPopUp`.
final class PlayerPopUpButton: NSPopUpButton {
    /// The bundle ID of the player the user picked.
    var onSelect: ((String) -> Void)?
    /// "Add a Web App…" was picked.
    var onAddWebApp: (() -> Void)?
    /// Learning the chosen player's controls again was picked.
    var onLearnAgain: (() -> Void)?
    /// The web apps' heading and note wrap at this width, so the note
    /// doesn't make the pop-up's menu as wide as itself.
    static let webAppsHeadingWidth: CGFloat = 280
    /// Marks the "Add a Web App…" item.
    private static let addWebAppMark = "addWebApp"
    /// Marks the item that learns the controls again.
    private static let learnAgainMark = "learnAgain"
    /// What the items show, so they're only rebuilt when it changes.
    private var shown: (options: [PlayerOption], selection: String?, learnAgainName: String?)?

    init() {
        super.init(frame: .zero, pullsDown: false)
        isBordered = false // plain, like the menu's player choice
        autoenablesItems = false
        target = self
        action = #selector(choose)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// SwiftUI calls this whenever Settings is drawn again (twice a second
    /// while a note blinks): the menu is rebuilt only for a change. The
    /// chosen item is always shown, also after a pick that wasn't taken.
    func update(options: [PlayerOption], selection: String?, learnAgainName: String? = nil) {
        defer {
            let chosen = itemArray.first { $0.representedObject as? String == selection } ?? itemArray.first
            if selectedItem !== chosen { select(chosen) }
        }
        if let shown, shown.options == options, shown.selection == selection, shown.learnAgainName == learnAgainName { return }
        shown = (options, selection, learnAgainName)
        removeAllItems()
        if selection == nil {
            let placeholder = NSMenuItem(
                title: String(localized: "Choose…", comment: "The menu's card and Settings' music player pop-up, while no music player is chosen"),
                action: nil, keyEquivalent: ""
            )
            placeholder.isEnabled = false
            menu?.addItem(placeholder)
        }
        for (index, option) in options.enumerated() {
            if index == options.webAppsStart { menu?.addItem(.webAppsHeading(width: Self.webAppsHeadingWidth)) }
            let item = NSMenuItem(title: option.name, action: nil, keyEquivalent: "")
            item.representedObject = option.bundleID
            item.image = option.icon(size: 16)
            if option.isUntested {
                item.setTitle(option.name, badge: PlayerOption.untestedBadge, font: font ?? .menuFont(ofSize: 0),
                              maxWidth: Self.webAppsHeadingWidth - 50)
            }
            if !option.isInstalled {
                item.isEnabled = option.isClickable
                item.subtitle = PlayerOption.notInstalledLabel
            }
            menu?.addItem(item)
        }
        menu?.addItem(.separator())
        if let learnAgainName {
            let again = NSMenuItem(title: LearningText.learnAgainItem, action: nil, keyEquivalent: "")
            again.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            again.subtitle = learnAgainName
            again.representedObject = Self.learnAgainMark
            menu?.addItem(again)
        }
        let add = NSMenuItem(title: PlayerOption.addWebAppTitle, action: nil, keyEquivalent: "")
        add.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil)
        add.representedObject = Self.addWebAppMark
        menu?.addItem(add)
    }

    @objc private func choose() {
        guard let picked = selectedItem?.representedObject as? String else { return }
        let isSuggestion = shown?.options.contains { $0.bundleID == picked && $0.webAddress != nil } ?? false
        let isAction = picked == Self.addWebAppMark || picked == Self.learnAgainMark
        if isAction || isSuggestion, let shown {
            // Not a player (yet): show the chosen one again.
            select(itemArray.first { $0.representedObject as? String == shown.selection } ?? itemArray.first)
        }
        if picked == Self.addWebAppMark {
            onAddWebApp?()
        } else if picked == Self.learnAgainMark {
            onLearnAgain?()
        } else {
            onSelect?(picked) // a suggested web app opens "Add a Web App"
        }
    }
}
