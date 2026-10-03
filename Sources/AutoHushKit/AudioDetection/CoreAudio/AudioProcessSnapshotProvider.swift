import CoreAudio
import Foundation
import OSLog

/// A CoreAudio client process.
package struct AudioProcessInfo: Equatable, Sendable {
    package let objectID: AudioObjectID
    package let bundleID: String
    package let pid: pid_t
    package let isRunningOutput: Bool
}

/// Source of CoreAudio process information. All methods are called on the
/// monitor's serial queue.
package protocol AudioProcessSnapshotProviding: AnyObject, Sendable {
    /// Processes that currently have audio output running.
    func activeProcesses() -> [AudioProcessInfo]
    /// Calls `onChange` on `queue` whenever the process list or any process's
    /// running state changes.
    func startObserving(on queue: DispatchQueue, onChange: @escaping @Sendable () -> Void)
    func stopObserving()
}

/// Reads processes from the CoreAudio HAL and observes it with block-based
/// property listeners.
package final class HALAudioProcessSnapshotProvider: AudioProcessSnapshotProviding, @unchecked Sendable {
    package init() {}

    private let logger = Logger(category: "AudioMonitor")
    private var queue: DispatchQueue?
    private var onChange: (@Sendable () -> Void)?
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var runningListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]

    package func activeProcesses() -> [AudioProcessInfo] {
        processObjectIDs().compactMap { objectID in
            // Read the cheap output flag first; only playing processes need more lookups.
            guard CoreAudioProperty.value(kAudioProcessPropertyIsRunningOutput, of: objectID, initial: UInt32(0)) == 1,
                  let bundleID = CoreAudioProperty.string(kAudioProcessPropertyBundleID, of: objectID)
            else { return nil }
            let pid = CoreAudioProperty.value(kAudioProcessPropertyPID, of: objectID, initial: pid_t(0)) ?? 0
            return AudioProcessInfo(objectID: objectID, bundleID: bundleID, pid: pid, isRunningOutput: true)
        }
    }

    package func startObserving(on queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        guard processListListener == nil else { return }
        self.queue = queue
        self.onChange = onChange

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.syncRunningListeners()
            onChange()
        }
        var address = CoreAudioProperty.address(kAudioHardwarePropertyProcessObjectList)
        let status = AudioObjectAddPropertyListenerBlock(CoreAudioProperty.systemObject, &address, queue, listener)
        if status == noErr {
            processListListener = listener
        } else {
            logger.error("[monitor] failed to register process list listener: \(status, privacy: .public)")
        }
        syncRunningListeners()
    }

    package func stopObserving() {
        if let listener = processListListener, let queue {
            var address = CoreAudioProperty.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(CoreAudioProperty.systemObject, &address, queue, listener)
        }
        processListListener = nil
        for objectID in Array(runningListeners.keys) {
            removeRunningListener(from: objectID)
        }
        onChange = nil
    }

    // MARK: Private

    /// Keeps one is-running listener per process object.
    ///
    /// `kAudioProcessPropertyIsRunningOutput` never sends change notifications
    /// (verified on macOS 27); `kAudioProcessPropertyIsRunning` does, so it is
    /// observed instead and the output flag is read when it fires.
    private func syncRunningListeners() {
        guard let queue, let onChange else { return }
        let current = processObjectIDs()
        for objectID in current where runningListeners[objectID] == nil {
            let listener: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
            var address = CoreAudioProperty.address(kAudioProcessPropertyIsRunning)
            let status = AudioObjectAddPropertyListenerBlock(objectID, &address, queue, listener)
            if status == noErr {
                runningListeners[objectID] = listener
            } else {
                logger.error("[monitor] failed to register is-running listener for object \(objectID, privacy: .public): \(status, privacy: .public)")
            }
        }
        for objectID in Array(runningListeners.keys) where !current.contains(objectID) {
            removeRunningListener(from: objectID)
        }
    }

    private func removeRunningListener(from objectID: AudioObjectID) {
        guard let listener = runningListeners.removeValue(forKey: objectID), let queue else { return }
        var address = CoreAudioProperty.address(kAudioProcessPropertyIsRunning)
        // Fails harmlessly when the process object is already gone.
        AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, listener)
    }

    private func processObjectIDs() -> Set<AudioObjectID> {
        Set(CoreAudioProperty.objectIDs(kAudioHardwarePropertyProcessObjectList, of: CoreAudioProperty.systemObject))
    }
}
