import Foundation

/// How much quieter the apps the music was paused for were than the music
/// (Settings → Advanced, "levelsMusic"): the music then resumes with the
/// Mac's volume lowered by as much (`SystemVolumeLeveler`).
///
/// The music's loudness is its level just before AutoHush paused it: the
/// loudest second of the last few it was heard (`musicWindow`), so the
/// fade-out before the pause doesn't count. The apps' is their average
/// level (root mean square) while heard during the pause, together, calls
/// (an app playing with its microphone on) left out: a voice says little
/// about how loud music should be.
struct ResumeLevel {
    /// How far back the music's loudness is looked for at a pause.
    static let musicWindow: TimeInterval = 6
    /// The stretch the music's loudness is averaged over (its loudest one counts).
    static let musicStretch: TimeInterval = 1

    /// The music's average levels while it was heard, oldest first.
    private var music: [(at: Date, rms: Float)] = []
    /// The music's loudness (rms) at the pause; `nil` while it isn't paused by us.
    private(set) var reference: Float?
    /// The apps' power (rms²) summed over the looks they were heard in during the pause, and how many.
    private var appsPower: Double = 0
    private var appsLooks = 0

    init() {}

    /// Notes the music's level, while it's measured and heard.
    mutating func noteMusic(rms: Float, at now: Date) {
        music.append((now, rms))
        music.removeAll { now.timeIntervalSince($0.at) > Self.musicWindow }
    }

    /// Notes the apps' level together, at a look they were heard in during
    /// the pause.
    mutating func noteApps(rms: Float) {
        guard reference != nil else { return }
        appsPower += Double(rms * rms)
        appsLooks += 1
    }

    /// The music was paused by AutoHush (its loudness just before then is
    /// the reference), or isn't any more (everything is forgotten).
    mutating func setMusicPaused(_ paused: Bool, at now: Date) {
        guard paused else {
            reference = nil
            appsPower = 0
            appsLooks = 0
            return
        }
        guard reference == nil else { return }
        let recent = music.filter { now.timeIntervalSince($0.at) <= Self.musicWindow }
        // The loudest stretch: the fade-out before the pause is quieter.
        reference = recent.map { start in
            let stretch = recent.filter { $0.at >= start.at && $0.at.timeIntervalSince(start.at) < Self.musicStretch }
            return Self.mean(stretch.map(\.rms))
        }.max()
        music.removeAll()
    }

    /// The apps' average level during the pause; `nil` when none was heard.
    var appsLevel: Float? {
        appsLooks == 0 ? nil : Float((appsPower / Double(appsLooks)).squareRoot())
    }

    /// How far (dB, below 0) to lower the volume as the music resumes:
    /// down to the apps' level, `maxCut` at most; `nil` when they weren't
    /// quieter by `minCut` or more, or either level is unknown.
    func offsetDB(maxCut: Float, minCut: Float) -> Float? {
        guard let reference, reference > 0, let apps = appsLevel, apps > 0 else { return nil }
        let difference = 20 * log10(apps / reference)
        guard difference <= -minCut else { return nil }
        return max(-maxCut, difference)
    }

    /// The root mean square of several root mean squares (their power averaged).
    private static func mean(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        return (values.map { $0 * $0 }.reduce(0, +) / Float(values.count)).squareRoot()
    }
}
