import AppKit

/// The menu bar AutoHush shows while one of its windows is open (it's in the
/// Dock then, `DockPresence`): a Mac app's standard menus, with Apple's
/// keyboard shortcuts and none of AutoHush's own. The Edit menu is what makes
/// ⌘X, ⌘C, ⌘V, ⌘A and ⌘Z work in text fields.
@MainActor
enum MainMenu {
    /// `about` and `settings` open those pages of Settings.
    static func make(about: @escaping @MainActor () -> Void, settings: @escaping @MainActor () -> Void) -> NSMenu {
        let bar = NSMenu()
        bar.addItem(submenu(appMenu(about: about, settings: settings), title: "AutoHush"))
        bar.addItem(submenu(editMenu(), title: editTitle))
        let window = windowMenu()
        bar.addItem(submenu(window, title: windowTitle))
        NSApplication.shared.windowsMenu = window
        return bar
    }

    private static func appMenu(about: @escaping @MainActor () -> Void, settings: @escaping @MainActor () -> Void) -> NSMenu {
        let menu = NSMenu(title: "AutoHush")
        menu.addItem(item(String(localized: "About AutoHush", comment: "The menu bar's AutoHush menu (while a window is open): opens Settings → About; macOS's own words, as in any app's menu"),
                          perform: about))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Settings…", comment: "The menu bar's AutoHush menu: opens Settings (⌘,); macOS's own word for an app's settings"),
                          key: ",", perform: settings))
        menu.addItem(.separator())
        let services = NSMenu()
        menu.addItem(submenu(services, title: String(localized: "Services", comment: "The menu bar's AutoHush menu: macOS's Services submenu; macOS's own word")))
        NSApplication.shared.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Hide AutoHush", comment: "The menu bar's AutoHush menu (⌘H); macOS's own words, as in any app's menu"),
                          #selector(NSApplication.hide(_:)), key: "h"))
        menu.addItem(item(String(localized: "Hide Others", comment: "The menu bar's AutoHush menu: hides the other apps (⌥⌘H); macOS's own words"),
                          #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]))
        menu.addItem(item(String(localized: "Show All", comment: "The menu bar's AutoHush menu: shows the hidden apps again; macOS's own words"),
                          #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quit AutoHush", comment: "The menu bar's AutoHush menu (⌘Q); macOS's own words, as in any app's menu"),
                          #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private static var editTitle: String {
        String(localized: "Edit", comment: "The menu bar: the Edit menu (cut, copy, paste); macOS's own word")
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: editTitle)
        menu.addItem(item(String(localized: "Undo", comment: "The menu bar's Edit menu (⌘Z); macOS's own word"), Selector(("undo:")), key: "z"))
        menu.addItem(item(String(localized: "Redo", comment: "The menu bar's Edit menu (⇧⌘Z); macOS's own word"), Selector(("redo:")), key: "z",
                          modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Cut", comment: "The menu bar's Edit menu (⌘X); macOS's own word"), #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(item(String(localized: "Copy", comment: "The menu bar's Edit menu (⌘C); macOS's own word"), #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(item(String(localized: "Paste", comment: "The menu bar's Edit menu (⌘V); macOS's own word"), #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(item(String(localized: "Delete", comment: "The menu bar's Edit menu: deletes the selected text; macOS's own word"), #selector(NSText.delete(_:))))
        menu.addItem(item(String(localized: "Select All", comment: "The menu bar's Edit menu (⌘A); macOS's own words"), #selector(NSText.selectAll(_:)), key: "a"))
        return menu
    }

    private static var windowTitle: String {
        String(localized: "Window", comment: "The menu bar: the Window menu; macOS's own word")
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: windowTitle)
        menu.addItem(item(String(localized: "Close", comment: "The menu bar's Window menu: closes the window (⌘W); macOS's own word"),
                          #selector(NSWindow.performClose(_:)), key: "w"))
        menu.addItem(item(String(localized: "Minimize", comment: "The menu bar's Window menu (⌘M); macOS's own word"),
                          #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(item(String(localized: "Zoom", comment: "The menu bar's Window menu: makes the window as big as it can be, or back; macOS's own word"),
                          #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Bring All to Front", comment: "The menu bar's Window menu; macOS's own words"),
                          #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    // MARK: - Items

    /// An item sent along the responder chain (the window, its text field…).
    private static func item(_ title: String, _ action: Selector, key: String = "",
                             modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    /// An item that runs `perform`.
    private static func item(_ title: String, key: String = "", perform: @escaping @MainActor () -> Void) -> NSMenuItem {
        let target = Target(perform)
        let item = NSMenuItem(title: title, action: #selector(Target.run), keyEquivalent: key)
        item.target = target
        item.representedObject = target // a menu item holds its target weakly
        return item
    }

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @MainActor
    private final class Target: NSObject {
        let perform: @MainActor () -> Void

        init(_ perform: @escaping @MainActor () -> Void) {
            self.perform = perform
        }

        @objc func run() { perform() }
    }
}
