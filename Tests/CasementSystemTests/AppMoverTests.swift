import Darwin
import Foundation
import CasementCore
import Testing
@testable import CasementSystem

/// Moving Casement to Applications, in a temporary folder with a Bin of the test's own.
@Suite struct AppMoverTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("casement-mover-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// A stand-in app with a file inside, marked as downloaded.
    func makeApp(at url: URL, version: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data(version.utf8).write(to: contents.appendingPathComponent("Info.plist"))
        for path in [url.path, contents.appendingPathComponent("Info.plist").path] {
            let value = "0081;00000000;Safari;"
            _ = value.withCString { setxattr(path, "com.apple.quarantine", $0, strlen($0), 0, XATTR_NOFOLLOW) }
        }
    }

    func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    final class Bin: @unchecked Sendable {
        var items: [String] = []
        var refuses: Set<String> = []
        func trash(_ url: URL) throws {
            if refuses.contains(url.lastPathComponent) { throw CocoaError(.fileWriteNoPermission) }
            items.append(url.path)
            try FileManager.default.removeItem(at: url)
        }
    }

    @Test func movesTheDownloadAndReplacesAnOlderCopy() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let downloaded = root.appendingPathComponent("Downloads/Casement.app")
        let destination = root.appendingPathComponent("Applications/Casement.app")
        try makeApp(at: downloaded, version: "new")
        try makeApp(at: destination, version: "old")
        let bin = Bin()
        try AppMover.move(downloaded, to: destination, original: downloaded, trash: bin.trash)
        let plist = destination.appendingPathComponent("Contents/Info.plist")
        #expect(String(decoding: try Data(contentsOf: plist), as: UTF8.self) == "new")
        // macOS already checked Casement when it opened, so the new copy isn't asked about again.
        #expect(!isQuarantined(destination))
        #expect(!isQuarantined(plist))
        // The old copy, then the download, went to the Bin.
        #expect(bin.items == [destination.path, downloaded.path])
        #expect(!FileManager.default.fileExists(atPath: downloaded.path))
    }

    @Test func intoAnApplicationsFolderThatIsntThereYet() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let translocatedCopy = root.appendingPathComponent("AppTranslocation/X/d/Casement.app")
        let destination = root.appendingPathComponent("home/Applications/Casement.app")
        try makeApp(at: translocatedCopy, version: "new")
        let bin = Bin()
        // macOS didn't say where the download is: nothing else goes to the Bin.
        try AppMover.move(translocatedCopy, to: destination, original: nil, trash: bin.trash)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/Info.plist").path))
        #expect(bin.items.isEmpty)
    }

    @Test func saysWhatWentWrong() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let downloaded = root.appendingPathComponent("Downloads/Casement.app")
        let destination = root.appendingPathComponent("Applications/Casement.app")
        try makeApp(at: downloaded, version: "new")
        try makeApp(at: destination, version: "old")
        let bin = Bin()
        bin.refuses = ["Casement.app"]
        #expect(throws: AppMover.MoveError.self) {
            try AppMover.move(downloaded, to: destination, original: downloaded, trash: bin.trash)
        }
        // Nothing was copied over the old one, and the download stays.
        #expect(String(decoding: try Data(contentsOf: destination.appendingPathComponent("Contents/Info.plist")), as: UTF8.self) == "old")
        #expect(FileManager.default.fileExists(atPath: downloaded.path))

        let missing = root.appendingPathComponent("Gone/Casement.app")
        do {
            try AppMover.move(missing, to: root.appendingPathComponent("Other/Casement.app"), original: nil, trash: Bin().trash)
            Issue.record("A copy that isn't there can't move")
        } catch let error as AppMover.MoveError {
            guard case .cannotCopy = error else { Issue.record("\(error)"); return }
            #expect(error.localizedDescription.hasPrefix("Casement couldn't copy itself to Applications"))
        }
    }

    @Test func aCopyThatIsntTranslocatedHasNoOtherOriginal() {
        #expect(AppMover.originalURL(of: URL(fileURLWithPath: "/Applications/Casement.app")) == nil)
    }
}
