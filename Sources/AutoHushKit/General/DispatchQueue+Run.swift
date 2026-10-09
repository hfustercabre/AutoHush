import Foundation

extension DispatchQueue {
    /// Runs `work` on this queue and waits for it, without holding one of
    /// Swift's shared threads meanwhile: for calls that block (Accessibility,
    /// Apple events, macOS's permission prompts), run one at a time.
    package func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            self.async { continuation.resume(returning: work()) }
        }
    }

    /// `run(_:)` for work that throws.
    package func runThrowing<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            self.async { continuation.resume(with: Result { try work() }) }
        }
    }
}
