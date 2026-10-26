import CoreAudio

/// Reads and sets properties of CoreAudio objects (on the global scope and
/// the main element unless asked otherwise), and finds a device's output
/// controls.
package enum CoreAudioProperty {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    /// Reads a fixed-size value; `nil` when the property cannot be read.
    package static func value<T: BitwiseCopyable>(
        _ selector: AudioObjectPropertySelector, of objectID: AudioObjectID,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, initial: T
    ) -> T? {
        var address = address(selector, scope: scope, element: element)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value : nil
    }

    /// Sets a fixed-size value; whether Core Audio took it.
    @discardableResult
    static func set<T: BitwiseCopyable>(
        _ selector: AudioObjectPropertySelector, of objectID: AudioObjectID,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, to value: T
    ) -> Bool {
        var address = address(selector, scope: scope, element: element)
        var value = value
        return AudioObjectSetPropertyData(objectID, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }

    package static func string(_ selector: AudioObjectPropertySelector, of objectID: AudioObjectID) -> String? {
        var address = address(selector)
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &unmanaged) == noErr else { return nil }
        return unmanaged?.takeRetainedValue() as String?
    }

    /// The output-scope address of a device's control (its mute, its
    /// volume), on one of its elements.
    static func outputAddress(_ selector: AudioObjectPropertySelector,
                              _ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        address(selector, scope: kAudioDevicePropertyScopeOutput, element: element)
    }

    /// The elements of a device's output control it can set: the main one,
    /// else those of its first two channels that can be (some devices have
    /// only those); none when it has no such control.
    static func settableOutputElements(_ selector: AudioObjectPropertySelector,
                                       of device: AudioObjectID) -> [AudioObjectPropertyElement] {
        if isSettable(selector, of: device, kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
        return ([1, 2] as [AudioObjectPropertyElement]).filter { isSettable(selector, of: device, $0) }
    }

    private static func isSettable(_ selector: AudioObjectPropertySelector, of device: AudioObjectID,
                                   _ element: AudioObjectPropertyElement) -> Bool {
        var address = outputAddress(selector, element)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    /// The device with this lasting ID (`kAudioDevicePropertyDeviceUID`)
    /// now: its object ID changes from one launch to the next.
    package static func device(withUID uid: String) -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var qualifier: CFString = uid as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &qualifier) { pointer in
            AudioObjectGetPropertyData(systemObject, &address, UInt32(MemoryLayout<CFString>.size), pointer, &size, &device)
        }
        return status == noErr && device != AudioObjectID(kAudioObjectUnknown) ? device : nil
    }

    static func objectIDs(_ selector: AudioObjectPropertySelector, of objectID: AudioObjectID) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &ids) == noErr else { return [] }
        // The list can shrink between the two calls (a process ending): only
        // what was written counts, not the zeros after it (object 0 is none).
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
}
