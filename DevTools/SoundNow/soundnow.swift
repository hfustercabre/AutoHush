// soundnow: the apps (by responsible process) whose audio output is running now (read only).
// Build: swiftc -O -o soundnow soundnow.swift
import AppKit
import CoreAudio

typealias Responsible = @convention(c) (pid_t) -> pid_t
let responsible = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")!, to: Responsible.self)

func get<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    return value
}

var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
let pids = Set(ids.filter { get($0, kAudioProcessPropertyIsRunningOutput, UInt32(0)) != 0 }.map { responsible(get($0, kAudioProcessPropertyPID, pid_t(0))) })
for pid in pids.sorted() { print(pid, NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?") }
if pids.isEmpty { print("silent") }
