import AppKit
import SwiftUI

/// Native radio buttons, one per option. An option can be unavailable: its
/// button is dimmed and can't be selected, but a click on it is reported, so
/// the view can say why. SwiftUI's radio-group picker can dim an option, but
/// not report clicks on it.
struct RadioChoices<Value: Hashable>: NSViewRepresentable {
    struct Option {
        let title: String
        let value: Value
        var isAvailable = true
    }

    let options: [Option]
    let selection: Value
    let onSelect: (Value) -> Void
    /// A click on an unavailable option, while the whole group is enabled.
    let onUnavailableClick: () -> Void

    func makeNSView(context: Context) -> RadioStack {
        RadioStack()
    }

    func updateNSView(_ view: RadioStack, context: Context) {
        let isEnabled = context.environment.isEnabled
        view.update(
            titles: options.map(\.title),
            enabled: options.map { isEnabled && $0.isAvailable },
            selected: options.firstIndex { $0.value == selection }
        )
        view.onSelect = { index in onSelect(options[index].value) }
        view.onUnavailableClick = isEnabled ? onUnavailableClick : nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RadioStack, context: Context) -> CGSize? {
        nsView.fittingSize
    }
}

/// A column of radio buttons that also catches clicks on its dimmed ones.
final class RadioStack: NSStackView {
    /// The index of the button the user chose.
    var onSelect: ((Int) -> Void)?
    /// A click on a dimmed button; nil when such clicks should do nothing.
    var onUnavailableClick: (() -> Void)?
    private(set) var buttons: [NSButton] = []

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 6
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(titles: [String], enabled: [Bool], selected: Int?) {
        if buttons.count != titles.count {
            buttons.forEach { $0.removeFromSuperview() }
            // Buttons with the same action in the same view work as one group.
            buttons = titles.map { NSButton(radioButtonWithTitle: $0, target: self, action: #selector(choose)) }
            buttons.forEach(addArrangedSubview)
        }
        for (index, button) in buttons.enumerated() {
            button.title = titles[index]
            button.isEnabled = enabled[index]
            button.state = index == selected ? .on : .off
        }
    }

    @objc private func choose(_ sender: NSButton) {
        guard let index = buttons.firstIndex(of: sender) else { return }
        onSelect?(index)
    }

    /// A dimmed button ignores clicks; this view takes them instead. Clicks
    /// between or beside the buttons belong to no option and pass through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit === self { return nil }
        guard onUnavailableClick != nil, let button = button(containing: hit), !button.isEnabled else { return hit }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard let onUnavailableClick else { return super.mouseDown(with: event) }
        onUnavailableClick()
    }

    /// The button `view` is, or is part of, among this stack's buttons.
    private func button(containing view: NSView?) -> NSButton? {
        var view = view
        while let current = view, current !== self {
            if let button = current as? NSButton, buttons.contains(button) { return button }
            view = current.superview
        }
        return nil
    }
}
