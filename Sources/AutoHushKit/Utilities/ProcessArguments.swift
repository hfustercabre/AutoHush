import Darwin

/// A process's launch arguments, its own path first, as `ps` reads them
/// (`KERN_PROCARGS2`: processes of the same user); empty when they can't be
/// read. Whether an app was opened with an option it needs (an Electron
/// app's `--disable-backgrounding-occluded-windows`).
package enum ProcessArguments {
    package static func of(_ pid: pid_t) -> [String] {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 4 else { return [] }
        let count = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        // After the count: the executable's path, NULs, then the arguments.
        var index = 4
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var found: [String] = []
        while found.count < count, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            found.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return found
    }
}
