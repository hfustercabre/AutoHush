import CoreAudio

/// The Mac's outputs: the one sound plays through now, and each one's
/// lasting ID. Muting them (`OutputMuting`) and their volume
/// (`SystemVolumeControlling`) find them so; Core Audio's by default, tests'
/// own outputs in memory.
package protocol OutputDevices: Sendable {
    /// The output sound plays through now.
    func defaultOutput() -> AudioObjectID?
    /// The output's lasting ID, and the output with it now: its object ID
    /// changes from one launch to the next.
    func uid(of device: AudioObjectID) -> String?
    func device(withUID uid: String) -> AudioObjectID?
}

extension OutputDevices {
    package func defaultOutput() -> AudioObjectID? {
        let device = CoreAudioProperty.value(kAudioHardwarePropertyDefaultOutputDevice, of: CoreAudioProperty.systemObject,
                                             initial: AudioObjectID(kAudioObjectUnknown))
        return device == AudioObjectID(kAudioObjectUnknown) ? nil : device
    }

    package func uid(of device: AudioObjectID) -> String? {
        CoreAudioProperty.string(kAudioDevicePropertyDeviceUID, of: device)
    }

    package func device(withUID uid: String) -> AudioObjectID? {
        CoreAudioProperty.device(withUID: uid)
    }
}
