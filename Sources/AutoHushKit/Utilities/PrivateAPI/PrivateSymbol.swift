import Darwin

/// A function of macOS's private frameworks, resolved at run time as window
/// managers resolve them: when a macOS update removes it, its callers get
/// `nil` and fall back, instead of the app failing to launch.
package enum PrivateSymbol {
    /// The function by the first of `names` found, as `type`: in the
    /// framework at `library` (opened first; `nil` when it can't be), else
    /// in what this process has loaded already; `nil` when none is.
    package static func function<T>(_ names: String..., in library: String? = nil, as type: T.Type) -> T? {
        let handle: UnsafeMutableRawPointer?
        if let library {
            guard let opened = dlopen(library, RTLD_NOW) else { return nil }
            handle = opened
        } else {
            handle = loaded
        }
        for name in names {
            if let found = dlsym(handle, name) { return unsafeBitCast(found, to: type) }
        }
        return nil
    }

    /// `RTLD_DEFAULT`, which Swift doesn't import: every image loaded.
    private static var loaded: UnsafeMutableRawPointer? { UnsafeMutableRawPointer(bitPattern: -2) }
}
