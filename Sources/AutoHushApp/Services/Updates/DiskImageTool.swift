import Foundation

/// A command-line tool that opens a disk image read-only at a given folder,
/// hidden from Finder, and closes it again.
struct DiskImageTool: Sendable {
    let path: String
    /// The arguments that open the image (first) at the mount point (second).
    let attachArguments: @Sendable (_ image: String, _ mountPoint: String) -> [String]
    /// The arguments that close the image opened at the mount point.
    let detachArguments: @Sendable (_ mountPoint: String) -> [String]

    /// `diskutil image`, which macOS 27 recommends. macOS 15 doesn't have it;
    /// 14.4's opened volumes the tests couldn't read, and its eject doesn't
    /// know `force`.
    static let diskutil = DiskImageTool(
        path: "/usr/sbin/diskutil",
        attachArguments: { ["image", "attach", "--readOnly", "--nobrowse", "--mountPoint", $1, $0] },
        detachArguments: { ["eject", "force", $0] }
    )

    /// hdiutil, on every macOS AutoHush supports, but deprecated for attaching
    /// and detaching since macOS 27. The image's own checksum isn't verified
    /// (seconds of work): the SHA-256 and the signature check already cover
    /// every byte that matters.
    static let hdiutil = DiskImageTool(
        path: "/usr/bin/hdiutil",
        attachArguments: { ["attach", $0, "-readonly", "-nobrowse", "-noautoopen", "-noverify", "-mountpoint", $1] },
        detachArguments: { ["detach", $0, "-force"] }
    )

    /// From macOS 27, which deprecates hdiutil's attach and detach, the newer
    /// tool first, so updates keep working once macOS removes them (when it
    /// fails, hdiutil takes over); before, hdiutil alone.
    static let inOrderOfPreference: [DiskImageTool] = if #available(macOS 27, *) { [diskutil, hdiutil] } else { [hdiutil] }
}
