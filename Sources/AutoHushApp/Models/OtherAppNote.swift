import Foundation

/// A note under Add an App's list on why the app picked can't be checked:
/// each one shown is new (its `id`), so VoiceOver hears it again when the
/// same problem comes twice (the 1.3.1 review's WA-2), and the problem and
/// that identity can't drift apart (the 1.3.2 review's S-2).
struct OtherAppNote: Identifiable, Equatable {
    let id = UUID()
    let problem: OtherAppProblem
}
