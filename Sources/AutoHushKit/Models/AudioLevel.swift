/// How loud a process was over a stretch of time.
package struct AudioLevel: Equatable, Sendable {
    /// Largest absolute sample value (0…1).
    var peak: Float
    /// Root-mean-square sample value (0…1): the average loudness.
    package var rms: Float
}
