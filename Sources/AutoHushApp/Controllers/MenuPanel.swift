import AppKit
import SwiftUI

/// The window AutoHush's menu shows in, under its menu bar item (the user,
/// 2026-10-17: smooth folding, as Maccy's and BetterDisplay's menus have):
/// a panel that takes the keyboard without making AutoHush the active app,
/// on the system's own menu material (Liquid Glass from macOS 26), which
/// follows Reduce Transparency and Increase Contrast. Its height follows its
/// content, animated, its top edge fixed (`setContentHeight`).
///
/// It's a titled window whose title bar is hidden, as Maccy's is: macOS
/// then rounds its shadow and border with its corners. A borderless one got
/// a square shadow, a dark line around its corners (2026-10-17).
final class MenuPanel: NSPanel {
    /// How long its height takes to follow its content (and the content's
    /// parts to fold and unfold: `MenuPanelView.animation`).
    static let resizeDuration: TimeInterval = 0.25
    static var cornerRadius: CGFloat {
        if #available(macOS 26, *) { 16 } else { 10 }
    }

    /// Escape: the menu closes.
    var onCancel: (() -> Void)?
    /// A key nothing in it took (the arrows and Return, for the players);
    /// `true` when handled.
    var onKey: ((NSEvent) -> Bool)?

    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: menuContentWidth, height: 100),
                   styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: true)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovable = false
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        // Not shown (its title bar is hidden), but VoiceOver names the window by it.
        title = "AutoHush"
        isExcludedFromWindowsMenu = true
        contentView = Self.background(around: content)
    }

    /// Whether it may take the keyboard: the menu's side window doesn't
    /// (the menu keeps it, so its switches stay drawn active), but for
    /// VoiceOver, which reads it.
    var takesKey = true

    override var canBecomeKey: Bool { takesKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    /// Takes the panel to `height`, its top edge where it is; animated
    /// (`resizeDuration`, easing out) unless `animated` is off.
    func setContentHeight(_ height: CGFloat, animated: Bool) {
        let height = height.rounded()
        guard abs(frame.height - height) >= 0.5 else { return }
        let target = NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
        guard animated else {
            setFrame(target, display: true)
            invalidateShadow()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.resizeDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.8, 0.25, 1)
            animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.invalidateShadow() }
        }
    }

    /// The system's menu material behind `content`, rounded.
    private static func background(around content: NSView) -> NSView {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }
}
