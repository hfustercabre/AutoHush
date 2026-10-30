import AppKit
import SwiftUI
import Testing
@testable import CheckPanel
import AutoHushTestSupport

/// The parts both apps' check panels draw (Add an App's and Player
/// Check's), drawn as the panel draws them: no test runs a check to the
/// step that shows them.
@Suite("The check panel's parts, drawn", .application)
@MainActor
struct CheckPanelPartsTests {
    /// Player Check's look (AutoHush's is made of its own colors, in its app).
    private let look = CheckPanelLook(caption: .caption, requestTint: .accentColor, requestFill: .accentColor.opacity(0.15),
                                      track: .secondary.opacity(0.22))
    /// The panel's width inside its margins.
    private let width: CGFloat = 282

    @Test("the window states draw as segments, the first, one between and the last, and as one with no count; a long activity wraps",
          arguments: [(1, 7), (4, 7), (7, 7), (1, 0)])
    func windowStep(index: Int, count: Int) {
        func step(_ activity: String) -> CheckWindowStepView {
            CheckWindowStepView(index: index, count: count, name: "Minimized", stepText: "\(index) of \(count)", activity: activity,
                                accessibilityText: "Window state \(index) of \(count): minimized. \(activity)", look: look)
        }
        let short = drawn(step("Pressing its menu"), width: width)
        #expect(short.height > 0)
        let long = drawn(step(String(repeating: "Pressing Play/Pause in its menu bar's Controls menu, then reading its state. ", count: 4)),
                         width: width)
        #expect(long.height > short.height)
    }

    @Test("what the check asks draws in the look's tint, with the time left under it, or alone")
    func requestNote() {
        let alone = drawn(CheckRequestNote("Start playing something in Jukebox", detail: "", symbol: "play.circle", look: look),
                          width: width)
        let withTime = drawn(CheckRequestNote("Start playing something in Jukebox", detail: "1:48 left", symbol: "play.circle", look: look),
                             width: width)
        #expect(alone.height > 0)
        #expect(withTime.height > alone.height)
    }

    /// Lays `view` out and draws it `width` wide, off screen, as the panel
    /// would (its text wraps there): a view that can't be drawn fails the
    /// test. Its size, as it fits.
    private func drawn(_ view: some View, width: CGFloat) -> NSSize {
        AutoHushTestSupport.drawn(view.frame(width: width), width: width, height: 400)
    }
}
