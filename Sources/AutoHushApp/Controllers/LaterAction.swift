import Foundation

/// What a window's view does once its window controller exists (`action`, set
/// after `super.init`): the view is made with `call` from the start and
/// never made again for it. Made first with `{}` and replaced once the
/// controller existed, a view's buttons ran the new actions on a click, but
/// SwiftUI kept the first view's for their keyboard shortcuts: Escape ran
/// `{}`, so Cancel never closed a guiding window by its key (the 1.3.0
/// live round, 2026-11-05; 1.2.9 too).
@MainActor
final class LaterAction {
    var action: () -> Void = {}
    var call: () -> Void { { [self] in action() } }
}

/// `LaterAction` for an action given a value (Add an App's `floats`).
@MainActor
final class LaterHandler<Input> {
    var action: (Input) -> Void = { _ in }
    var call: (Input) -> Void { { [self] input in action(input) } }
}
