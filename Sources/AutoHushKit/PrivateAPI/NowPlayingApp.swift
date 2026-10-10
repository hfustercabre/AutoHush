import Foundation
import os

/// The app macOS counts as "Now Playing": the one the keyboard's Play/Pause
/// key and Control Center's media controls reach, whichever app was meant.
///
/// Read through MediaRemote, a private framework, resolved at runtime:
/// `MRMediaRemoteNowPlayingResolvePlayerPath` on a player path with no
/// client answers with the app in Now Playing. It's one of the few questions
/// MediaRemote still answers for apps without Apple's entitlement (checked
/// on macOS 27). If a macOS update removes it, or it doesn't answer, the
/// answer is `.unknown`, and callers do as before they asked.
///
/// Within one process MediaRemote keeps giving its first answer, however
/// Now Playing changes since, so `current()` asks a fresh copy of the running
/// executable, which answers through `printAnswer()` and quits.
///
/// Check after every major macOS release.
package enum NowPlayingApp {
    package enum Answer: Equatable, Sendable {
        /// The process in Now Playing: an app, or the helper that plays for
        /// it (WebKit's media process, for a web app or Safari).
        case process(pid_t)
        /// No app is in Now Playing.
        case none
        /// MediaRemote didn't answer, or can't be asked.
        case unknown
    }

    /// The argument that makes the executable answer once and quit, before
    /// anything else starts.
    package static let argument = "--now-playing"

    /// Now Playing as it stands, from a fresh copy of `executable` (this
    /// one by default). Blocks for up to `timeout`.
    package static func current(executable: URL? = Bundle.main.executableURL, timeout: TimeInterval = 2) -> Answer {
        guard let executable else { return .unknown }
        let child = Process()
        child.executableURL = executable
        child.arguments = [argument]
        let output = Pipe()
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        child.terminationHandler = { _ in finished.signal() }
        guard (try? child.run()) != nil else { return .unknown }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            child.terminate()
            return .unknown
        }
        return answer(from: String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    /// In the fresh copy: MediaRemote's answer, as `current()` reads it.
    package static func printAnswer() {
        switch resolve() {
        case .process(let pid): print("process \(pid)")
        case .none: print("none")
        case .unknown: print("unknown")
        }
    }

    /// What the copy printed.
    package static func answer(from output: String) -> Answer {
        let words = output.split(whereSeparator: \.isWhitespace).map(String.init)
        switch words.first {
        case "process"?:
            guard words.count == 2, let pid = pid_t(words[1]), pid > 0 else { return .unknown }
            return .process(pid)
        case "none"?: return .none
        default: return .unknown
        }
    }

    // MARK: - MediaRemote

    private typealias Ref = UnsafeRawPointer
    private typealias GetLocalOrigin = @convention(c) () -> Ref?
    /// (origin, client, player).
    private typealias CreatePath = @convention(c) (Ref?, Ref?, Ref?) -> Ref?
    private typealias ResolvePath = @convention(c) (Ref?, Ref, @escaping @convention(block) (Ref?, Ref?) -> Void) -> Void
    private typealias PathGetClient = @convention(c) (Ref?) -> Ref?
    private typealias ClientGetPID = @convention(c) (Ref?) -> Int32

    private struct Functions: Sendable {
        let localOrigin: GetLocalOrigin
        let createPath: CreatePath
        let resolvePath: ResolvePath
        let pathClient: PathGetClient
        let clientPID: ClientGetPID
    }

    private static let functions: Functions? = {
        guard let framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            return nil
        }
        func symbol<T>(_ name: String, _ type: T.Type) -> T? {
            dlsym(framework, name).map { unsafeBitCast($0, to: type) }
        }
        guard let localOrigin = symbol("MRMediaRemoteGetLocalOrigin", GetLocalOrigin.self),
              let createPath = symbol("MRNowPlayingPlayerPathCreate", CreatePath.self),
              let resolvePath = symbol("MRMediaRemoteNowPlayingResolvePlayerPath", ResolvePath.self),
              let pathClient = symbol("MRNowPlayingPlayerPathGetClient", PathGetClient.self),
              let clientPID = symbol("MRNowPlayingClientGetProcessIdentifier", ClientGetPID.self)
        else { return nil }
        return Functions(localOrigin: localOrigin, createPath: createPath, resolvePath: resolvePath,
                         pathClient: pathClient, clientPID: clientPID)
    }()

    /// MediaRemote's answer in this process (its first is kept: see the
    /// type's comment).
    static func resolve(timeout: TimeInterval = 1) -> Answer {
        guard let functions, let path = functions.createPath(functions.localOrigin(), nil, nil) else { return .unknown }
        defer { Unmanaged<AnyObject>.fromOpaque(path).release() }
        let answer = OSAllocatedUnfairLock<Answer>(initialState: .unknown)
        let answered = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "AutoHush.NowPlayingApp")
        functions.resolvePath(path, UnsafeRawPointer(Unmanaged.passUnretained(queue).toOpaque())) { resolved, error in
            defer { answered.signal() }
            guard error == nil else { return }
            let pid = functions.pathClient(resolved).map(functions.clientPID) ?? 0
            answer.withLock { $0 = pid > 0 ? .process(pid) : .none }
        }
        guard answered.wait(timeout: .now() + timeout) == .success else { return .unknown }
        return answer.withLock { $0 }
    }
}
