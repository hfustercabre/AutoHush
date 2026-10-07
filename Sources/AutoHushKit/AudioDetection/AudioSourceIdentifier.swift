import Darwin
import Foundation
import os

/// The app behind one or more audio processes, e.g. "Google Chrome" for all
/// of Chrome's helper processes.
package struct AudioSource: Hashable, Sendable {
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

/// Finds the app behind a process.
package protocol AudioSourceIdentifying: Sendable {
    /// The app that owns an audio process.
    func source(for process: AudioProcessInfo) -> AudioSource
    /// The owning app of any process (e.g. one holding a power assertion), or `nil`.
    func sourceID(forPID pid: pid_t) -> String?
}

/// Finds the app that owns an audio process.
///
/// Browsers and other apps often play audio from helper processes (Chrome's
/// "Google Chrome Helper", WebKit's GPU process). The owner is found by:
///   1. the process macOS holds responsible for it (`ProcessResponsibility`,
///      a private function; it also covers XPC services such as WebKit's that
///      live outside any app);
///   2. for that process, then for the process itself: the app it runs as,
///      when `hostedApp` knows it, else the outermost bundle in its executable
///      path (public `proc_pidpath`);
///   3. otherwise the process's own bundle ID, shown as is (empty for a
///      command-line program no app owns).
/// Results are cached per process.
package final class ProcessAudioSourceIdentifier: AudioSourceIdentifying, Sendable {
    /// The app a process runs as when its executable belongs to another
    /// program: every Safari web app runs Safari's one "Web App" program, so
    /// its path alone would name them all alike. `nil` for other processes.
    private let hostedApp: @Sendable (pid_t) -> AudioSource?

    package init(hostedApp: @escaping @Sendable (pid_t) -> AudioSource? = { _ in nil }) {
        self.hostedApp = hostedApp
    }

    /// Owner of each audio process; its bundle ID (or, without one, its
    /// executable path) guards against pid reuse.
    private let sources = ProcessCache<AudioSource>()
    /// Owner of any process; its executable path guards against pid reuse.
    private let owners = ProcessCache<String?>()

    package func source(for process: AudioProcessInfo) -> AudioSource {
        let key = process.bundleID.isEmpty ? Self.executablePath(of: process.pid) ?? "" : process.bundleID
        return sources.value(for: process.pid, key: key) { resolve(process) }
    }

    package func sourceID(forPID pid: pid_t) -> String? {
        guard let path = Self.executablePath(of: pid) else { return nil } // the process is gone
        return owners.value(for: pid, key: path) { resolveOwner(of: pid)?.id }
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
            if let source = hostedApp(candidate) { return source }
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

/// Remembers one value per process. `key` (something about the process that
/// changes when its pid is reused) must match for a remembered value to count.
private final class ProcessCache<Value: Sendable>: Sendable {
    /// Past this many entries all are dropped: most belong to processes that quit.
    private static var limit: Int { 256 }
    private let entries = OSAllocatedUnfairLock<[pid_t: (key: String, value: Value)]>(initialState: [:])

    /// The remembered value, or a newly computed one (computed outside the lock).
    func value(for pid: pid_t, key: String, compute: () -> Value) -> Value {
        if let entry = entries.withLock({ $0[pid] }), entry.key == key { return entry.value }
        let value = compute()
        entries.withLock { entries in
            if entries.count > Self.limit { entries.removeAll() }
            entries[pid] = (key, value)
        }
        return value
    }
}
