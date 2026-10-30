import Foundation
import Security
import AutoHushKit

// UpdateInstaller: the checks of the app copied out (its signature, version
// and macOS), and its quarantine mark.
extension UpdateInstaller {
    /// Accepts `app` only when it's signed like the running app, intact (every
    /// file, every architecture and any nested code), and is `version`. The
    /// version is read after the signature check, which covers Info.plist.
    func check(_ app: URL, isVersion version: AppVersion) throws {
        guard let requirement, Self.isSigned(app, satisfying: requirement) else { throw UpdateInstallError.notGenuine }
        let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist"))
        // A release candidate's number is its own key (`AppVersion(info:)`).
        guard let found = (info as? [String: Any]).flatMap(AppVersion.init(info:)), found == version
        else { throw UpdateInstallError.wrongVersion }
        // Swapped in, an app that needs a newer macOS wouldn't open.
        if let minimum = info?["LSMinimumSystemVersion"] as? String,
           !Self.isAtLeast(minimum, ProcessInfo.processInfo.operatingSystemVersion) {
            throw UpdateInstallError.needsNewerMacOS(minimum)
        }
    }

    /// Whether `system` is `minimum` ("14.4", "15", "15.0.1") or later; an
    /// unreadable minimum doesn't hold an update back.
    static func isAtLeast(_ minimum: String, _ system: OperatingSystemVersion) -> Bool {
        let parts = minimum.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return true }
        let needed = parts.compactMap { $0 } + [0, 0]
        let have = [system.majorVersion, system.minorVersion, system.patchVersion]
        return !have.lexicographicallyPrecedes(needed.prefix(3))
    }

    static func isSigned(_ app: URL, satisfying requirementText: String) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess
        else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    /// The running app's designated requirement, such as `identifier
    /// "com.autohush.AutoHush" and anchor apple generic and certificate
    /// leaf[subject.OU] = "BNT2VN4LH5"` (its developer team) and its
    /// certificate issued by Apple's developer authority (`team_requirement`
    /// in Scripts/lib/common.sh), or nil when it isn't signed with a
    /// certificate (ad hoc or not at all).
    static func runningAppRequirement() -> String? {
        var running: SecCode?
        var code: SecStaticCode?
        var information: CFDictionary?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let certificates = (information as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
              !certificates.isEmpty,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess
        else { return nil }
        return text as String?
    }

    /// Removes the "downloaded from the internet" mark from `app` and
    /// everything inside it.
    static func removeQuarantine(from app: URL) {
        let contents = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for url in [app] + contents {
            url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return }
                removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW)
            }
        }
    }
}
