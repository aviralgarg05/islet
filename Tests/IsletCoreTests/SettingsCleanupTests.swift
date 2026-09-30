import Foundation
import Testing
@testable import IsletCore

private func decode(_ json: String) -> IsletSettings { IsletSettings.decodeLenient(Data(json.utf8)) }

private func writtenKeys(_ s: IsletSettings) throws -> Set<String> {
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any]
    return Set(object?.keys.map { $0 } ?? [])
}

@Suite struct AppRuleMigrationTests {
    @Test func oldListsBecomeRules() {
        let s = decode(#"{"fullscreenAllowList": ["us.zoom.xos"], "hideForApps": ["com.valvesoftware.steam"]}"#)
        #expect(s.appRules == [
            AppRule(bundleID: "us.zoom.xos", showInFullscreen: true),
            AppRule(bundleID: "com.valvesoftware.steam", hideIsland: true),
        ])
    }

    @Test func mergesIntoAnExistingRuleForTheSameApp() {
        let s = decode(#"""
        {"appRules": [{"bundleID": "us.zoom.xos", "tint": "blue", "muteNotifications": true}],
         "fullscreenAllowList": ["us.zoom.xos"], "hideForApps": ["us.zoom.xos"]}
        """#)
        #expect(s.appRules.count == 1)
        let zoom = s.rule(for: "us.zoom.xos")
        #expect(zoom?.tint == "blue")
        #expect(zoom?.muteNotifications == true)
        #expect(zoom?.showInFullscreen == true)
        #expect(zoom?.hideIsland == true)
    }

    @Test func listEntryWinsOverAnExplicitFalse() {
        // The old lists were ORed with the rule, so an app on a list kept that behaviour.
        let s = decode(#"{"appRules": [{"bundleID": "a.b", "showInFullscreen": false}], "fullscreenAllowList": ["a.b"]}"#)
        #expect(s.appRules == [AppRule(bundleID: "a.b", showInFullscreen: true)])
    }

    @Test func noDuplicatesOrBlankRules() {
        let s = decode(#"{"fullscreenAllowList": ["a.b", "a.b", " ", ""], "hideForApps": ["c.d", " c.d "]}"#)
        #expect(s.appRules.map(\.bundleID) == ["a.b", "c.d"])
    }

    @Test func existingRulesKeepTheirOrder() {
        let rules = [AppRule(bundleID: "x"), AppRule(bundleID: "y", tint: "red")]
        let merged = AppRule.merging(rules, showInFullscreen: ["z", "y"], hideIsland: ["x"])
        #expect(merged.map(\.bundleID) == ["x", "y", "z"])
        #expect(merged[0].hideIsland == true)
        #expect(merged[1].showInFullscreen == true && merged[1].tint == "red")
        #expect(merged[2].showInFullscreen == true && merged[2].hideIsland == nil)
        #expect(AppRule.merging(rules, showInFullscreen: [], hideIsland: []) == rules)
    }

    @Test func malformedListsAreIgnored() {
        let s = decode(#"{"hideForApps": "com.valvesoftware.steam", "fullscreenAllowList": [1, 2], "hoverToOpen": false}"#)
        #expect(s.appRules.isEmpty)
        #expect(s.hoverToOpen == false)
    }

    @Test func oldKeysAreNotWrittenBack() throws {
        let s = decode(#"{"fullscreenAllowList": ["us.zoom.xos"], "hideForApps": ["com.apple.Keynote"], "launchAtLogin": true}"#)
        let keys = try writtenKeys(s)
        #expect(!keys.contains("fullscreenAllowList"))
        #expect(!keys.contains("hideForApps"))
        #expect(!keys.contains("launchAtLogin"))
        #expect(keys.contains("appRules"))
        // Loading what was saved gives the same settings: the migration runs once.
        let again = IsletSettings.decodeLenient(try JSONEncoder().encode(s))
        #expect(again == s)
    }

    @Test func oldLaunchAtLoginIsIgnored() throws {
        let s = decode(#"{"launchAtLogin": true, "hoverToOpen": false}"#)
        var expected = IsletSettings()
        expected.hoverToOpen = false
        #expect(s == expected)
        let keys = try writtenKeys(IsletSettings())
        #expect(!keys.contains("launchAtLogin"))
    }
}

@Suite struct ClosedLayoutMigrationTests {
    @Test func oldDropLayoutLoadsAsAutomatic() {
        // "drop" hung a pill below the notch. The island now always sits beside it.
        let s = decode(#"{"closedLayout": "drop", "wingWidth": 60, "hoverToOpen": false}"#)
        #expect(s.closedLayout == .auto)
        // The other keys still load.
        #expect(s.wingWidth == 60)
        #expect(s.hoverToOpen == false)
    }

    @Test func oldDropLayoutIsNotWrittenBack() throws {
        let s = decode(#"{"closedLayout": "drop"}"#)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any]
        #expect(object?["closedLayout"] as? String == "auto")
        #expect(IsletSettings.decodeLenient(try JSONEncoder().encode(s)) == s)
    }

    @Test func oldDropLayoutInAConfigFileIsReplacedOnSave() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("islet-layout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"closedLayout": "drop", "sizePreset": "standard"}"#.utf8).write(to: file)
        let s = IsletSettings.load(from: file)
        #expect(s.closedLayout == .auto)
        #expect(s.sizePreset == .standard)
        try s.save(to: file)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains("\"drop\""))
        #expect(IsletSettings.load(from: file) == s)
    }

    @Test func remainingChoicesStillLoad() {
        #expect(decode(#"{"closedLayout": "wings"}"#).closedLayout == .wings)
        #expect(decode(#"{"closedLayout": "auto"}"#).closedLayout == .auto)
        #expect(ClosedLayoutPreference.allCases == [.auto, .wings])
    }
}

@Suite struct SettingsRangeTests {
    typealias Ranged = (WritableKeyPath<IsletSettings, Double>, ClosedRange<Double>)
    static var ranged: [Ranged] { [
        (\.openDelay, IsletSettings.openDelayRange),
        (\.closeDelay, IsletSettings.closeDelayRange),
        (\.expandedWidth, IsletSettings.expandedWidthRange),
        (\.expandedHeight, IsletSettings.expandedHeightRange),
        (\.wingWidth, IsletSettings.wingWidthRange),
        (\.alertDuration, IsletSettings.alertDurationRange),
        (\.hudDuration, IsletSettings.hudDurationRange),
    ] }

    @Test func sanitizeClampsToTheSameRangesAsTheSliders() {
        for (key, range) in Self.ranged {
            var low = IsletSettings(), high = IsletSettings()
            low[keyPath: key] = range.lowerBound - 1000
            high[keyPath: key] = range.upperBound + 1000
            #expect(low.sanitized()[keyPath: key] == range.lowerBound)
            #expect(high.sanitized()[keyPath: key] == range.upperBound)
            var edge = IsletSettings()
            edge[keyPath: key] = range.upperBound
            #expect(edge.sanitized()[keyPath: key] == range.upperBound)
        }
        var s = IsletSettings()
        s.clipboardLimit = 0
        #expect(s.sanitized().clipboardLimit == IsletSettings.clipboardLimitRange.lowerBound)
        s.clipboardLimit = 100_000
        #expect(s.sanitized().clipboardLimit == IsletSettings.clipboardLimitRange.upperBound)
    }

    @Test func defaultsAndPresetsFitTheRanges() {
        let d = IsletSettings()
        #expect(d.sanitized() == d)
        for (key, range) in Self.ranged { #expect(range.contains(d[keyPath: key])) }
        #expect(IsletSettings.clipboardLimitRange.contains(d.clipboardLimit))
        for preset in SizePreset.allCases {
            guard let size = preset.dimensions else { continue }
            #expect(IsletSettings.expandedWidthRange.contains(size.width))
            #expect(IsletSettings.expandedHeightRange.contains(size.height))
            #expect(IsletSettings.wingWidthRange.contains(size.wing))
        }
    }

    @Test func handEditedValuesOutsideTheRangeAreClampedOnLoad() {
        let s = decode(#"{"expandedHeight": 5000, "wingWidth": 1, "hudDuration": 0, "alertDuration": 60, "closeDelay": -1}"#)
        #expect(s.expandedHeight == IsletSettings.expandedHeightRange.upperBound)
        #expect(s.wingWidth == IsletSettings.wingWidthRange.lowerBound)
        #expect(s.hudDuration == IsletSettings.hudDurationRange.lowerBound)
        #expect(s.alertDuration == IsletSettings.alertDurationRange.upperBound)
        #expect(s.closeDelay == 0)
    }
}

@Suite struct PortTests {
    @Test func portProblems() {
        #expect(IsletSettings.portProblem(47831, other: 47832) == nil)
        #expect(IsletSettings.portProblem(1024, other: 65535) == nil)
        #expect(IsletSettings.portProblem(80, other: 47832) != nil)
        #expect(IsletSettings.portProblem(70000, other: 47832) != nil)
        #expect(IsletSettings.portProblem(nil, other: 47832) != nil)
        #expect(IsletSettings.portProblem(47832, other: 47832) != nil)
    }

    @Test func sanitizeKeepsThePortsApart() {
        let d = IsletSettings()
        var s = IsletSettings()
        s.apiPort = d.lanPort
        s.lanPort = d.lanPort
        let fixed = s.sanitized()
        #expect(fixed.apiPort == d.lanPort)
        #expect(fixed.lanPort != fixed.apiPort)
        #expect(IsletSettings.portProblem(fixed.lanPort, other: fixed.apiPort) == nil)
        s.apiPort = 50000
        s.lanPort = 99
        #expect(s.sanitized().lanPort == d.lanPort)
    }
}
