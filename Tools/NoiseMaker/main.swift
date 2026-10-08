// Noise Maker: a test app for AutoHush in the VM. It plays a tone or a file
// for a while and quits, so AutoHush sees "another app" playing. It has no
// Dock icon or window, so it never takes the focus.
//
//   open -n ~/vmtools/NoiseMaker.app --args [--tone <hz>] [--file <path>]
//        [--seconds <n>|inf] [--volume <0…1>]
//
// Defaults: a 440 Hz tone for 8 s at volume 0.5. A file loops for the time
// given. It quits early on SIGTERM. Each start and stop is appended to
// /tmp/noisemaker.log as "<epoch seconds> start|stop …".
import AppKit
import AVFoundation

let arguments = CommandLine.arguments

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

let seconds = Double(option("--seconds") ?? "8") ?? 8
let volume = Float(option("--volume") ?? "0.5") ?? 0.5

func log(_ line: String) {
    let text = String(format: "%.3f ", Date().timeIntervalSince1970) + line + "\n"
    let url = URL(fileURLWithPath: "/tmp/noisemaker.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(text.utf8))
        try? handle.close()
    } else {
        try? Data(text.utf8).write(to: url)
    }
}

final class Noise {
    private let engine = AVAudioEngine()
    private var player: AVAudioPlayer?

    /// Starts playing; says what.
    func start() throws -> String {
        if let path = option("--file") {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player.numberOfLoops = -1
            player.volume = volume
            player.play()
            self.player = player
            return "file \(path)"
        }
        let frequency = Double(option("--tone") ?? "440") ?? 440
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let step = 2 * Double.pi * frequency / rate
        var phase = 0.0
        let source = AVAudioSourceNode(format: format) { _, _, frames, buffers in
            let start = phase
            for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
                let samples = buffer.mData!.assumingMemoryBound(to: Float.self)
                for frame in 0..<Int(frames) {
                    samples[frame] = Float(sin(start + step * Double(frame))) * volume
                }
            }
            phase = (start + step * Double(frames)).truncatingRemainder(dividingBy: 2 * Double.pi)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        try engine.start()
        return "tone \(frequency) Hz"
    }

    func stop() {
        player?.stop()
        engine.stop()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let noise = Noise()
do {
    let what = try noise.start()
    log("start \(what) for \(seconds) s, pid \(getpid())")
} catch {
    log("failed: \(error)")
    exit(1)
}
if seconds.isFinite {
    Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
        noise.stop()
        log("stop")
        exit(0)
    }
}
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    noise.stop()
    log("stop (terminated)")
    exit(0)
}
termination.resume()
app.run()
