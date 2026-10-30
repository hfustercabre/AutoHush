import Foundation

/// What an app's binaries link, read from their Mach-O load commands, as
/// `NowPlayingReason.of(appAt:bundleID:)` needs it.
package enum MachOFile {
    /// The frameworks a Mach-O file links ("MediaPlayer" for
    /// /System/Library/Frameworks/MediaPlayer.framework/…), from its load
    /// commands: the arm64 slice of a universal file, else its first; empty
    /// for a file that isn't 64-bit Mach-O.
    package static func linkedFrameworks(_ url: URL) -> Set<String> {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        func read(_ offset: UInt64, _ count: Int) -> Data? {
            guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.read(upToCount: count), data.count == count else { return nil }
            return data
        }
        func word(_ data: Data, _ offset: Int, bigEndian: Bool = false) -> UInt32 {
            let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            return bigEndian ? UInt32(bigEndian: value) : value
        }
        guard let head = read(0, 8) else { return [] }
        var slice: UInt64 = 0
        switch word(head, 0) {
        case 0xbeba_feca, 0xbfba_feca: // universal (FAT_MAGIC, FAT_MAGIC_64, big-endian)
            let wide = word(head, 0) == 0xbfba_feca
            let count = Int(word(head, 4, bigEndian: true)), size = wide ? 32 : 20
            guard (1...16).contains(count), let table = read(8, count * size) else { return [] }
            var chosen: UInt64?
            for index in 0..<count {
                let base = index * size
                let offset = wide ? UInt64(word(table, base + 8, bigEndian: true)) << 32 | UInt64(word(table, base + 12, bigEndian: true))
                                  : UInt64(word(table, base + 8, bigEndian: true))
                if word(table, base, bigEndian: true) == 0x0100_000c { chosen = offset; break } // arm64
                if chosen == nil { chosen = offset }
            }
            slice = chosen ?? 0
        case 0xfeed_facf: break // MH_MAGIC_64
        default: return []
        }
        guard let header = read(slice, 32), word(header, 0) == 0xfeed_facf else { return [] }
        let commands = Int(word(header, 16)), size = Int(word(header, 20))
        guard size < 1 << 22, let table = read(slice + 32, size) else { return [] }
        // LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_LAZY_LOAD_DYLIB, LC_LOAD_UPWARD_DYLIB
        let linking: Set<UInt32> = [0xc, 0x8000_0018, 0x8000_001f, 0x20, 0x8000_0023]
        var names = Set<String>()
        var offset = 0
        for _ in 0..<commands {
            guard offset + 12 <= table.count else { break }
            let length = Int(word(table, offset + 4))
            guard length >= 12, offset + length <= table.count else { break }
            if linking.contains(word(table, offset)) {
                let start = offset + Int(word(table, offset + 8))
                if start < offset + length {
                    let path = String(decoding: table[start..<(offset + length)].prefix { $0 != 0 }, as: UTF8.self)
                    if let end = path.range(of: ".framework/"), let name = path[..<end.lowerBound].split(separator: "/").last {
                        names.insert(String(name))
                    }
                }
            }
            offset += length
        }
        return names
    }
}
