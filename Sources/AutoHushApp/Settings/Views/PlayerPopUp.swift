import AppKit
import SwiftUI

/// A native pop-up of the music players, with their icons. A player that
/// isn't installed is dimmed, marked "Not installed", and can't be chosen;
/// while none is chosen, a placeholder asks for one. SwiftUI's menu picker
/// can't dim a single option.
struct PlayerPopUp: NSViewRepresentable {
    let options: [PlayerOption]
    /// The chosen player's bundle ID; `nil` while none is chosen.
    let selection: String?
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> PlayerPopUpButton {
        PlayerPopUpButton()
    }

    func updateNSView(_ view: PlayerPopUpButton, context: Context) {
        view.update(options: options, selection: selection)
        view.onSelect = onSelect
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
    /// What the items show, so they're only rebuilt when it changes.
    private var shown: (options: [PlayerOption], selection: String?)?

    init() {
        super.init(frame: .zero, pullsDown: false)
        autoenablesItems = false
        target = self
        action = #selector(choose)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// SwiftUI calls this whenever Settings is drawn again (twice a second
    /// while a note blinks): the menu is rebuilt only for a change. The
    /// chosen item is always shown, also after a pick that wasn't taken.
    func update(options: [PlayerOption], selection: String?) {
        defer {
            let chosen = itemArray.first { $0.representedObject as? String == selection } ?? itemArray.first
            if selectedItem !== chosen { select(chosen) }
        }
        if let shown, shown.options == options, shown.selection == selection { return }
        shown = (options, selection)
        removeAllItems()
        if selection == nil {
            let placeholder = NSMenuItem(
                title: String(localized: "Choose…", comment: "Settings: the music player pop-up while none is chosen"),
                action: nil, keyEquivalent: ""
            )
            placeholder.isEnabled = false
            menu?.addItem(placeholder)
        }
        for option in options {
            let item = NSMenuItem(title: option.name, action: nil, keyEquivalent: "")
            item.representedObject = option.bundleID
            item.image = option.icon(size: 16)
            if !option.isInstalled {
                item.isEnabled = false
                item.subtitle = PlayerOption.notInstalledLabel
            }
            menu?.addItem(item)
        }
    }

    @objc private func choose() {
        guard let bundleID = selectedItem?.representedObject as? String else { return }
        onSelect?(bundleID)
    }
}
