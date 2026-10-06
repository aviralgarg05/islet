import Darwin
import Foundation
import CasementCore

/// Moves Casement to Applications when it runs from Downloads, and opens it again from there
/// (`AppLocation` decides when to offer, and what the offer says). Nothing happens without the
/// user's click.
public enum AppMover {
    public enum MoveError: LocalizedError, Equatable {
        case cannotReplace(String)
        case cannotCopy(String)

        public var errorDescription: String? {
            switch self {
            case .cannotReplace(let why): return "The copy of Casement already in Applications couldn't go to the Bin (\(why))."
            case .cannotCopy(let why): return "Casement couldn't copy itself to Applications (\(why))."
            }
        }
    }

    /// The copy a translocated app was opened from (in Downloads, say), as macOS tells it. Nil
    /// when Casement isn't translocated or macOS won't say.
    public static func originalURL(of bundle: URL) -> URL? {
        guard AppLocation.isTranslocated(bundlePath: bundle.path),
              let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY) else { return nil }
        defer { dlclose(security) }
        guard let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        typealias Original = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let original = unsafeBitCast(symbol, to: Original.self)
        guard let found = original(bundle as CFURL, nil)?.takeRetainedValue() else { return nil }
        let url = found as URL
        return url.standardizedFileURL == bundle.standardizedFileURL ? nil : url
    }

    /// Copies `bundle` to `destination`, putting a copy already there in the Bin first, and
    /// lets macOS run the new copy from there: the download quarantine is cleared on it, since
    /// macOS already checked Casement when it first opened. Then `original`, the copy that was
    /// downloaded, goes to the Bin; if it can't, it stays where it is, which is harmless.
    /// - Parameter trash: puts a file in the Bin (tests pass their own).
    public static func move(_ bundle: URL, to destination: URL, original: URL?, trash: (URL) throws -> Void) throws {
        let fm = FileManager.default
        try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            do { try trash(destination) } catch { throw MoveError.cannotReplace(error.localizedDescription) }
        }
        do { try fm.copyItem(at: bundle, to: destination) } catch { throw MoveError.cannotCopy(error.localizedDescription) }
        clearQuarantine(at: destination)
        if let original, original.standardizedFileURL != destination.standardizedFileURL {
            try? trash(original)
        }
    }

    /// The Bin, as Finder does it.
    public static func moveToBin(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Clears the download quarantine on `url` and everything inside it.
    public static func clearQuarantine(at url: URL) {
        let name = "com.apple.quarantine"
        removexattr(url.path, name, XATTR_NOFOLLOW)
        guard let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        for case let item as URL in items {
            removexattr(item.path, name, XATTR_NOFOLLOW)
        }
    }

    /// Opens the app at `url` once this process has quit (`AppLocation.reopenArguments`).
    public static func reopen(at url: URL) throws {
        let args = AppLocation.reopenArguments(pid: ProcessInfo.processInfo.processIdentifier, appPath: url.path)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        try p.run()
    }
}
