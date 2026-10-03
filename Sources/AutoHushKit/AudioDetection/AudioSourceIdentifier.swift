import Darwin
import Foundation
import os

/// The app behind one or more audio processes, e.g. "Google Chrome" for all
/// of Chrome's helper processes.
package struct AudioSource: Equatable, Hashable, Sendable {
    /// Bundle identifier of the owning app (or of the process when no app is found).
    package let id: String
    package let name: String
    /// Path of the owning bundle, for its icon.
    package let bundlePath: String?

    package init(id: String, name: String, bundlePath: String? = nil) {
        self.id = id
        self.name = name
        self.bundlePath = bundlePath
    }
}

extension Sequence<AudioSource> {
    /// Sorted by name as people read it (case-insensitive), then by ID.
    package func sortedByName() -> [AudioSource] {
        sorted { ($0.name.localizedLowercase, $0.id) < ($1.name.localizedLowercase, $1.id) }
    }
}

package protocol AudioSourceIdentifying: Sendable {
    func source(for process: AudioProcessInfo) -> AudioSource
    /// The owning app of any process (e.g. one holding a power assertion), or `nil`.
    func sourceID(forPID pid: pid_t) -> String?
}

extension AudioSourceIdentifying {
    package func sourceID(forPID pid: pid_t) -> String? { nil }
}

/// Finds the app that owns an audio process.
///
/// Browsers and other apps often play audio from helper processes (Chrome's
/// "Google Chrome Helper", WebKit's GPU process). The owner is found by:
///   1. the process macOS holds responsible for it (`ProcessResponsibility`,
///      a private function; it also covers XPC services such as WebKit's that
///      live outside any app);
///   2. otherwise the outermost bundle in the process's executable path (public `proc_pidpath`);
///   3. otherwise the process's own bundle ID, shown as is.
/// Results are cached per process.
package final class ProcessAudioSourceIdentifier: AudioSourceIdentifying, @unchecked Sendable {
    package init() {}

    /// Keyed by pid; the process's own bundle ID guards against pid reuse.
    private let cache = OSAllocatedUnfairLock<[pid_t: (bundleID: String, source: AudioSource)]>(initialState: [:])

    package func source(for process: AudioProcessInfo) -> AudioSource {
        if let cached = cache.withLock({ $0[process.pid] }), cached.bundleID == process.bundleID {
            return cached.source
        }
        let source = resolve(process)
        cache.withLock { cache in
            if cache.count > 256 { cache.removeAll() } // entries of processes that quit
            cache[process.pid] = (process.bundleID, source)
        }
        return source
    }

    /// Keyed by pid; the executable path guards against pid reuse.
    private let ownerCache = OSAllocatedUnfairLock<[pid_t: (path: String, id: String?)]>(initialState: [:])

    package func sourceID(forPID pid: pid_t) -> String? {
        guard let path = Self.executablePath(of: pid) else { return nil } // the process is gone
        if let cached = ownerCache.withLock({ $0[pid] }), cached.path == path { return cached.id }
        let id = resolveOwner(of: pid)?.id
        ownerCache.withLock { cache in
            if cache.count > 256 { cache.removeAll() }
            cache[pid] = (path, id)
        }
        return id
    }

    private func resolve(_ process: AudioProcessInfo) -> AudioSource {
        resolveOwner(of: process.pid) ?? AudioSource(id: process.bundleID, name: process.bundleID)
    }

    private func resolveOwner(of pid: pid_t) -> AudioSource? {
        var pids = [pid]
        if let owner = ProcessResponsibility.responsiblePID(for: pid), owner != pid {
            pids.insert(owner, at: 0)
        }
        for candidate in pids {
            if let path = Self.executablePath(of: candidate),
               let bundleURL = Self.outermostBundle(containing: path),
               let source = Self.source(forBundleAt: bundleURL) {
                return source
            }
        }
        return nil
    }

    package static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    /// The outermost `.app` in the path, else the outermost `.appex` or `.xpc`.
    package static func outermostBundle(containing path: String) -> URL? {
        let components = (path as NSString).pathComponents
        for extensions in [["app"], ["appex", "xpc"]] {
            if let index = components.firstIndex(where: { extensions.contains(($0 as NSString).pathExtension) }) {
                return URL(fileURLWithPath: NSString.path(withComponents: Array(components[...index])))
            }
        }
        return nil
    }

    package static func source(forBundleAt url: URL) -> AudioSource? {
        guard let identifier = Bundle(url: url)?.bundleIdentifier else { return nil }
        let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        return AudioSource(id: identifier, name: name.isEmpty ? identifier : name, bundlePath: url.path)
    }
}
