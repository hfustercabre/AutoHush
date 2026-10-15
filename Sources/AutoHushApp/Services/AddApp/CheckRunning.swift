/// A check running, for the model: Stop, and how it ended.
@MainActor
protocol CheckRunning: AnyObject {
    func stop()
    /// How it ended, once it has; more than one may wait.
    func waitForEnd() async -> PlayerCheckEnd
}

extension PlayerCheckRun: CheckRunning {}
