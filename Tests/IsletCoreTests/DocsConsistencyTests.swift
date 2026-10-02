import Foundation
import Testing
@testable import IsletCore

/// The README and the changelog say how many apps have their own Live Activity look; that
/// number comes from the catalogue, so it must match it.
@Suite struct DocsConsistencyTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func text(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func appCountsMatchTheCatalogue() throws {
        let count = LiveActivityCatalog.apps.count
        let readme = try text("README.md")
        #expect(readme.contains("\(count) apps have their own look"), "README.md")
        let changelog = try text("CHANGELOG.md")
        #expect(changelog.contains("\(count) apps get their own icon, colour and layout"), "CHANGELOG.md")
        let architecture = try text("docs/ARCHITECTURE.md")
        #expect(architecture.contains("`LiveActivityCatalog` holds \(count) apps"), "docs/ARCHITECTURE.md")
    }

    @Test func theAskDocsDescribeTheSwitcher() throws {
        #expect(!(try text("docs/AI.md")).contains("**sparkles** button"))
    }

    /// The island's chip changes the saved provider, the one Settings shows; only a link's
    /// provider lasts just until the island closes.
    @Test func theAskDocsSayTheChipIsTheSetting() throws {
        let doc = try text("docs/AI.md")
        #expect(!doc.contains("Change provider for this session"))
        #expect(doc.contains("same setting as Settings → Ask & AI → Answer with"))
        #expect(doc.contains("picks the provider until the island closes"))
    }

    /// The chips offer every player macOS lists, and the bridge's commands go only to the one
    /// macOS gives the controls to; the docs say so.
    @Test func theNowPlayingDocsDescribeEveryPlayer() throws {
        let architecture = try text("docs/ARCHITECTURE.md")
        #expect(architecture.contains("MRMediaRemoteGetNowPlayingClients"))
        #expect(architecture.contains("through the bridge only when macOS gives that app the controls"))
        #expect(!architecture.contains("only when the bridge is reporting that app"))
        #expect(try text("docs/API.md").contains("through the system's Now Playing when macOS gives that app the controls"))
        #expect(try text("README.md").contains("switch between every player macOS lists"))
        let helper = try text("Helpers/MediaRemoteBridge/IsletMediaRemote.m")
        #expect(helper.contains("{\"type\":\"players\",\"players\":[<player>, ...]}"))
    }

    /// mediaremoted sends a targeted command from Islet's helper to the current player instead,
    /// so the helper must never even look one up: a pause for a Safari tab would pause Chrome.
    @Test func theHelperLoadsOnlyUntargetedCommands() throws {
        let helper = try text("Helpers/MediaRemoteBridge/IsletMediaRemote.m")
        let pattern = try NSRegularExpression(pattern: #"dlsym\(gMR, "(\w+)"\)"#)
        let names = Set(pattern.matches(in: helper, range: NSRange(helper.startIndex..., in: helper)).compactMap {
            Range($0.range(at: 1), in: helper).map { String(helper[$0]) }
        })
        #expect(names == [
            "MRMediaRemoteGetNowPlayingInfo", "MRMediaRemoteRegisterForNowPlayingNotifications",
            "MRMediaRemoteGetNowPlayingApplicationIsPlaying", "MRMediaRemoteGetNowPlayingClient",
            "MRMediaRemoteGetNowPlayingClients", "MRMediaRemoteGetNowPlayingInfoForPlayer",
            "MRMediaRemoteSendCommand", "MRMediaRemoteSetElapsedTime", "MRMediaRemoteSetShuffleMode",
            "MRMediaRemoteSetRepeatMode",
        ])
        // Nor named anywhere else in code (the comment that warns against them names them unquoted).
        for targeted in ["SendCommandToApp", "SendCommandToClient", "SendCommandToPlayer", "SendCommandToPlayerWithResult",
                         "SetElapsedTimeForPlayer", "SetShuffleModeForPlayer", "SetRepeatModeForPlayer"] {
            #expect(!helper.contains("\"MRMediaRemote\(targeted)\""), "\(targeted)")
        }
    }
}
