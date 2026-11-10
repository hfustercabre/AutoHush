import CoreGraphics
import Foundation

// KeyHighlight: what waits for a later turn of the run loop (the controls
// registered and placed, a scroll done).
extension KeyHighlight {
    /// The highlight on the first control as soon as they've come (a side
    /// window just opened by →, as a submenu's first item lights up).
    func highlightFirstWhenReady() {
        wantsFirst = true
        firstWhenReady()
    }

    /// The innermost control that takes the highlight around `element`, on
    /// screen in `screenFrame`'s coordinates: the element VoiceOver's cursor
    /// is on (`VoiceOverCursor`), its middle in the control, and no more than
    /// 24 pt wider or taller (a window or a page around it isn't the
    /// control). `nil` off its controls, or not placed on screen.
    func control(around element: CGRect) -> UUID? {
        guard let screenFrame else { return nil }
        let middle = CGPoint(x: element.midX, y: element.midY)
        return controls.compactMap { id, control -> (UUID, CGRect)? in
            guard control.isEnabled || control.explains, let rect = screenFrame(control.frame), rect.contains(middle),
                  element.width <= rect.width + 24, element.height <= rect.height + 24 else { return nil }
            return (id, rect)
        }.min { $0.1.width * $0.1.height < $1.1.width * $1.1.height }?.0
    }

    /// Zoom shows the control the keys moved to, once it's scrolled into
    /// view (the reveal takes 0.15 s), if the highlight is still there.
    func followWithZoom(_ id: UUID) {
        guard screenFrame != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.revealed == id, let frame = self.controls[id]?.frame,
                      let rect = self.screenFrame?(frame) else { return }
                self.zoom(rect)
            }
        }
    }

    /// Once the controls that came in the same update have registered (the
    /// next turn of the run loop) and been placed: a frame that comes later
    /// tries again (`update(_:frame:)`), so it never lights one at random.
    func firstWhenReady() {
        guard wantsFirst, !controls.isEmpty else { return }
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.wantsFirst, !self.controls.isEmpty,
                      !self.controls.values.contains(where: { $0.frame == .zero }) else { return }
                self.wantsFirst = false
                if self.highlighted == nil { self.move(1) }
            }
        }
    }

    /// The highlight on the first control of `group` that takes it (a
    /// card's first usable row), once what the press changed is drawn: a
    /// row it turns on or off has registered so by then.
    func highlightFirst(in group: UUID) {
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let first = self.rows.joined().first(where: { self.controls[$0]?.group == group }) else { return }
                self.highlight(first)
            }
        }
    }
}
