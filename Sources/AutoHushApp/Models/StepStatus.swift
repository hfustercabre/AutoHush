/// Where a step stands and whether AutoHush is doing it now: what the mark
/// beside it shows (`StepSymbol`), in a checklist or Add an App's numbered
/// steps (`NumberedStepRow`).
struct StepStatus: Equatable {
    let state: StepState
    /// AutoHush is doing it now (its state is `current` then): a spinner
    /// instead of its mark.
    var isBusy = false
}
