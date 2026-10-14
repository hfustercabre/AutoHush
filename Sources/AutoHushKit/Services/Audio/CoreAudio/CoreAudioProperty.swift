import CoreAudio

/// Reads global-scope properties of CoreAudio objects.
package enum CoreAudioProperty {
    package static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    package static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Reads a fixed-size value; `nil` when the property cannot be read.
    package static func value<T: BitwiseCopyable>(
        _ selector: AudioObjectPropertySelector, of objectID: AudioObjectID, initial: T
    ) -> T? {
        var address = address(selector)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value : nil
    }

    package static func string(_ selector: AudioObjectPropertySelector, of objectID: AudioObjectID) -> String? {
        var address = address(selector)
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &unmanaged) == noErr else { return nil }
        return unmanaged?.takeRetainedValue() as String?
    }

    package static func objectIDs(_ selector: AudioObjectPropertySelector, of objectID: AudioObjectID) -> [AudioObjectID] {
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
