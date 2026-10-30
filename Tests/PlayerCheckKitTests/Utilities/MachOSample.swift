import Foundation

/// Mach-O files made for the test: a 64-bit one linking `frameworks`, and a
/// universal one holding it as its arm64 slice.
enum MachOSample {
    static func thin(linking frameworks: [String]) -> Data {
        var commands = Data()
        for name in frameworks {
            var path = Data("/System/Library/Frameworks/\(name).framework/Versions/A/\(name)".utf8)
            path.append(0)
            while (24 + path.count) % 8 != 0 { path.append(0) }
            commands.append(words([0xc, UInt32(24 + path.count), 24, 0, 0, 0]))
            commands.append(path)
        }
        var file = words([0xfeed_facf, 0x0100_000c, 0, 2, UInt32(frameworks.count), UInt32(commands.count), 0, 0])
        file.append(commands)
        return file
    }

    static func universal(linking frameworks: [String]) -> Data {
        let slice = thin(linking: frameworks)
        var file = Data([0xca, 0xfe, 0xba, 0xbe]) + bigEndian([2])
        // An x86_64 slice first (pointing at the same bytes), then arm64's.
        file += bigEndian([0x0100_0007, 3, 64, UInt32(slice.count), 0])
        file += bigEndian([0x0100_000c, 0, 64, UInt32(slice.count), 0])
        file += Data(count: 64 - file.count)
        return file + slice
    }

    static func words(_ values: [UInt32]) -> Data { values.reduce(into: Data()) { data, value in withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } } }
    static func bigEndian(_ values: [UInt32]) -> Data { values.reduce(into: Data()) { data, value in withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } } }

    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
