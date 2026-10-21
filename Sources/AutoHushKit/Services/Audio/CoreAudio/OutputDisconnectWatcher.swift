import CoreAudio
import Foundation

/// Tells when the output sound plays through goes away: unplugged, out of
/// range, or taken by another device (AirPods moving to an iPhone). macOS then
/// plays on another output, often the speakers (Pause on disconnect,
/// Settings → Behavior). Choosing another output yourself isn’t
/// that: the one left is still there.
package protocol OutputDisconnectWatching: AnyObject, Sendable {
    /// Calls `onDisconnect` each time the output in use goes away, until `stop()`.
    func start(onDisconnect: @escaping @Sendable () -> Void)
    func stop()
}

/// `OutputDisconnectWatching` through Core Audio. The output in use is
/// followed (`kAudioHardwarePropertyDefaultOutputDevice`); it goes away when
/// it leaves the list of devices (Bluetooth, USB, AirPods; on Apple silicon
/// the headphone jack's own "External Headphones" too), or when its jack says
/// nothing is plugged in any more (the headphone jack of older Macs). Two
/// signs of one disconnect (the device leaving and the output in use
/// changing, in either order: `OutputLoss`) count once.
///
/// `@unchecked Sendable`: its state is only read and changed on `queue`,
/// where every listener runs; `start` and `stop` hop onto it.
package final class CoreAudioOutputDisconnectWatcher: OutputDisconnectWatching, @unchecked Sendable {
    package init() {}

    /// Signs closer together than this are one disconnect.
    static let sameDisconnect: TimeInterval = 2

    private let queue = DispatchQueue(label: "com.autohush.AutoHush.output-disconnects")
    private let logger = AutoHushLogger(category: "OutputDisconnects")
    private var onDisconnect: (@Sendable () -> Void)?
    /// The output in use, and whether something is plugged into its jack
    /// (`nil` for one without a jack to tell).
    private var output: AudioObjectID?
    private var jackConnected: Bool?
    private var lastDisconnect: Date?
    /// The output in use and the one just left (`check`).
    private var loss = OutputLoss()
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var jackListener: AudioObjectPropertyListenerBlock?

    private static let systemSelectors = [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices]
    private static var jackAddress: AudioObjectPropertyAddress {
        CoreAudioProperty.outputAddress(kAudioDevicePropertyJackIsConnected, kAudioObjectPropertyElementMain)
    }

    package func start(onDisconnect: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            guard self.onDisconnect == nil else { return }
            self.onDisconnect = onDisconnect
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.check() }
            systemListener = listener
            for selector in Self.systemSelectors {
                var address = CoreAudioProperty.address(selector)
                AudioObjectAddPropertyListenerBlock(CoreAudioProperty.systemObject, &address, queue, listener)
            }
            follow(Self.defaultOutput())
        }
    }

    package func stop() {
        queue.sync {
            if let systemListener {
                for selector in Self.systemSelectors {
                    var address = CoreAudioProperty.address(selector)
                    AudioObjectRemovePropertyListenerBlock(CoreAudioProperty.systemObject, &address, queue, systemListener)
                }
            }
            systemListener = nil
            follow(nil)
            loss = OutputLoss()
            onDisconnect = nil
        }
    }

    /// The devices or the output in use changed: the one in use is gone
    /// if it left the list, or the one just left (`OutputLoss`).
    private func check() {
        let current = Self.defaultOutput()
        if let reason = loss.update(output: output, current: current, devices: Self.devices(), now: Date()) {
            disconnected(because: reason)
        }
        if current != output { follow(current) }
    }

    /// Follows `device` as the output in use: its jack, if it has one.
    private func follow(_ device: AudioObjectID?) {
        if let output, let jackListener {
            var address = Self.jackAddress
            AudioObjectRemovePropertyListenerBlock(output, &address, queue, jackListener)
        }
        jackListener = nil
        output = device
        jackConnected = nil
        guard let device else { return }
        var address = Self.jackAddress
        guard AudioObjectHasProperty(device, &address) else { return }
        jackConnected = Self.jackIsConnected(device)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.jackChanged() }
        if AudioObjectAddPropertyListenerBlock(device, &address, queue, listener) == noErr { jackListener = listener }
    }

    private func jackChanged() {
        guard let output else { return }
        let connected = Self.jackIsConnected(output)
        if jackConnected == true, !connected { disconnected(because: "its jack was unplugged") }
        jackConnected = connected
    }

    private func disconnected(because reason: String) {
        let now = Date()
        if let lastDisconnect, now.timeIntervalSince(lastDisconnect) < Self.sameDisconnect { return }
        lastDisconnect = now
        logger.info("[outputs] the output in use went away: \(reason, privacy: .public)")
        onDisconnect?()
    }

    private static func defaultOutput() -> AudioObjectID? {
        let device = CoreAudioProperty.value(kAudioHardwarePropertyDefaultOutputDevice, of: CoreAudioProperty.systemObject,
                                             initial: AudioObjectID(kAudioObjectUnknown))
        return device == AudioObjectID(kAudioObjectUnknown) ? nil : device
    }

    private static func devices() -> [AudioObjectID] {
        CoreAudioProperty.objectIDs(kAudioHardwarePropertyDevices, of: CoreAudioProperty.systemObject)
    }

    private static func jackIsConnected(_ device: AudioObjectID) -> Bool {
        CoreAudioProperty.value(kAudioDevicePropertyJackIsConnected, of: device, scope: kAudioDevicePropertyScopeOutput,
                                initial: UInt32(0)) == 1
    }
}

/// Whether the output in use went away, from what Core Audio says as the
/// devices or the output in use change. macOS may announce the next output
/// before the old one leaves the devices: the output just left is watched
/// for `CoreAudioOutputDisconnectWatcher.sameDisconnect` too, so its leaving
/// still counts. One that stays was chosen by the user: no disconnect.
struct OutputLoss {
    /// The output in use before the last change, and when it changed.
    private var left: (device: AudioObjectID, at: Date)?

    /// `output`: the one followed until now; `current`: the one in use now.
    /// Why the output in use went away, or `nil` when it didn't.
    mutating func update(output: AudioObjectID?, current: AudioObjectID?, devices: [AudioObjectID], now: Date) -> String? {
        if let left, now.timeIntervalSince(left.at) >= CoreAudioOutputDisconnectWatcher.sameDisconnect { self.left = nil }
        if let output, !devices.contains(output) {
            left = nil
            return "it left the devices"
        }
        if let gone = left?.device, !devices.contains(gone) {
            left = nil
            return "it left the devices after the output in use changed"
        }
        if let output, current != output { left = (output, now) }
        return nil
    }
}
