import CoreAudio
import Foundation

/// Tells when the output sound plays through goes away: unplugged, out of
/// range, or taken by another device (AirPods moving to an iPhone). macOS then
/// plays on another output, often the speakers (Pause on disconnect,
/// Settings → Detection). Choosing another output yourself isn't
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
/// signs of one disconnect (the device leaving, then the output in use
/// changing) count once.
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
            onDisconnect = nil
        }
    }

    /// The devices or the output in use changed: the one in use is gone
    /// if it left the list.
    private func check() {
        if let output, !Self.devices().contains(output) { disconnected(because: "it left the devices") }
        let current = Self.defaultOutput()
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
