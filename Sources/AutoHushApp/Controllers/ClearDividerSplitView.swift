import AppKit

/// A split view whose divider is drawn clear (`SettingsSplitViewController`).
final class ClearDividerSplitView: NSSplitView {
    override var dividerColor: NSColor { .clear }
}
