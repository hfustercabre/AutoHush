import AppKit
import SwiftUI

/// One choice among a few, as macOS's segmented control (the user,
/// 2026-10-17): AntiDot mode's ways of detecting, what happens when an
/// update is found. It's AppKit's, whose segments are as wide as their
/// words (SwiftUI's makes each as wide as the widest, which didn't fit), and
/// it fills its row in proportion. The room it needs (`fittingWidth`) sets
/// Settings' and the menu's least width in each language. In the menu it's
/// the small one (`.controlSize(.small)`, C2).
struct ChoiceChips<Value: Hashable>: NSViewRepresentable {
    struct Option {
        let title: String
        let value: Value
    }

    let options: [Option]
    let selection: Value
    let onSelect: (Value) -> Void

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = Self.control(options.map(\.title), size: context.environment.controlSize)
        control.segmentDistribution = .fillProportionally
        control.target = context.coordinator
        control.action = #selector(Coordinator.chosen(_:))
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.choice = self
        let size = NSControl.ControlSize(context.environment.controlSize)
        if control.controlSize != size {
            control.controlSize = size
            control.font = .systemFont(ofSize: NSFont.systemFontSize(for: size))
        }
        for (index, option) in options.enumerated() where control.label(forSegment: index) != option.title {
            control.setLabel(option.title, forSegment: index)
        }
        control.selectedSegment = options.firstIndex { $0.value == selection } ?? -1
        control.isEnabled = context.environment.isEnabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView control: NSSegmentedControl, context: Context) -> CGSize? {
        let fitting = control.fittingSize
        return CGSize(width: max(fitting.width, proposal.width ?? fitting.width), height: fitting.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(choice: self) }

    @MainActor final class Coordinator: NSObject {
        var choice: ChoiceChips

        init(choice: ChoiceChips) { self.choice = choice }

        @objc func chosen(_ control: NSSegmentedControl) {
            guard choice.options.indices.contains(control.selectedSegment) else { return }
            choice.onSelect(choice.options[control.selectedSegment].value)
        }
    }

    /// AppKit's segmented control with these titles, at `size`.
    private static func control(_ titles: [String], size: ControlSize) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: titles, trackingMode: .selectOne, target: nil, action: nil)
        control.controlSize = NSControl.ControlSize(size)
        control.font = .systemFont(ofSize: NSFont.systemFontSize(for: control.controlSize))
        return control
    }
}

extension ChoiceChips where Value == Never {
    /// The width a choice of these titles needs at `size`, each segment as
    /// wide as its words: the least room it's given.
    @MainActor static func fittingWidth(_ titles: [String], size: ControlSize = .regular) -> CGFloat {
        ceil(control(titles, size: size).fittingSize.width)
    }
}

private extension NSControl.ControlSize {
    init(_ size: ControlSize) {
        switch size {
        case .mini: self = .mini
        case .small: self = .small
        case .large, .extraLarge: self = .large
        default: self = .regular
        }
    }
}
