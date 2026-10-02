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
}
