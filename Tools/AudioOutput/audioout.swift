// audioout get | list | set <UID>: the default output device (and the alerts' one with set).
// Build: swiftc -O -o audioout audioout.swift
import CoreAudio
import Foundation

func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func string(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var addr = address(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr, let value else { return "" }
    return value.takeRetainedValue() as String
}

func devices() -> [AudioObjectID] {
    var addr = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
    return ids
}

func hasOutput(_ device: AudioObjectID) -> Bool {
    var addr = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size)
    return size > 0
}

func current(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
    var addr = address(selector)
    var device = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
    return device
}

func set(_ selector: AudioObjectPropertySelector, _ device: AudioObjectID) -> OSStatus {
    var addr = address(selector)
    var device = device
    return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &device)
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "get" {
case "list":
    for device in devices() where hasOutput(device) {
        print("\(string(device, kAudioDevicePropertyDeviceUID))\t\(string(device, kAudioObjectPropertyName))")
    }
case "set":
    guard args.count > 2, let device = devices().first(where: { string($0, kAudioDevicePropertyDeviceUID) == args[2] }) else {
        print("no output device with UID \(args.count > 2 ? args[2] : "?")"); exit(1)
    }
    let output = set(kAudioHardwarePropertyDefaultOutputDevice, device)
    let alerts = set(kAudioHardwarePropertyDefaultSystemOutputDevice, device)
    print("output: \(string(device, kAudioObjectPropertyName))", output == noErr && alerts == noErr ? "" : "(errors \(output), \(alerts))")
default:
    let device = current(kAudioHardwarePropertyDefaultOutputDevice)
    print("\(string(device, kAudioDevicePropertyDeviceUID))\t\(string(device, kAudioObjectPropertyName))")
}
