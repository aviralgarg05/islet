import Foundation
import Testing
@testable import CasementCore

@Suite struct StatusLineSetupTests {
    let cli = "/Applications/Casement.app/Contents/MacOS/casementctl"

    func text(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

    func statusLine(_ d: Data) -> [String: Any]? {
        ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any])?["statusLine"] as? [String: Any]
    }

    @Test func setsItWhenAbsentKeepingTheRestOfTheFile() throws {
        let settings = """
        {
          "model": "opus",
          "hooks": {
            "Stop": [{"hooks": [{"type": "command", "command": "afplay /System/Library/Sounds/Glass.aiff"}]}]
          }
        }

        """
        let edit = try ClaudeStatusLineSetup.install(into: Data(settings.utf8), cli: cli)
        #expect(edit.before == nil)
        #expect(edit.after == "\(cli) statusline")
        #expect(text(edit.settings) == """
        {
          "model": "opus",
          "hooks": {
            "Stop": [{"hooks": [{"type": "command", "command": "afplay /System/Library/Sounds/Glass.aiff"}]}]
          },
          "statusLine": {
            "type": "command",
            "command": "\(cli) statusline"
          }
        }

        """)
        #expect(ClaudeStatusLineSetup.status(of: edit.settings) == .installed(original: nil))
    }

    @Test func wrapsAnExistingCommandWithoutOverwritingIt() throws {
        let settings = #"{"statusLine": {"type": "command", "command": "~/.claude/statusline.sh | head -1", "padding": 0}, "theme": "dark"}"#
        let edit = try ClaudeStatusLineSetup.install(into: Data(settings.utf8), cli: cli)
        #expect(edit.before == "~/.claude/statusline.sh | head -1")
        #expect(edit.after == "\(cli) statusline -- '~/.claude/statusline.sh | head -1'")
        let line = try #require(statusLine(edit.settings))
        #expect(line["command"] as? String == edit.after)
        #expect(line["padding"] as? Int == 0)
        #expect(text(edit.settings).hasSuffix(#", "padding": 0}, "theme": "dark"}"#))
        #expect(ClaudeStatusLineSetup.status(of: edit.settings) == .installed(original: "~/.claude/statusline.sh | head -1"))
    }

    @Test func installingTwiceChangesNothing() throws {
        for settings in ["{}", #"{"statusLine":{"type":"command","command":"bun x ccstatusline@latest"}}"#] {
            let once = try ClaudeStatusLineSetup.install(into: Data(settings.utf8), cli: cli)
            #expect(once.changesFile)
            let twice = try ClaudeStatusLineSetup.install(into: once.settings, cli: cli)
            #expect(!twice.changesFile)
            #expect(twice.settings == once.settings)
            // Also when the CLI moved: a wrapper is recognised by name, not by path.
            #expect(!(try ClaudeStatusLineSetup.install(into: once.settings, cli: "/opt/homebrew/bin/casementctl")).changesFile)
        }
    }

    @Test func quotesAwkwardCommandsSoTheShellGetsThemBack() throws {
        let original = #"printf '%s' "$(jq -r .model.display_name)""#
        let settings = try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": original]])
        let edit = try ClaudeStatusLineSetup.install(into: settings, cli: "/Users/me/Apps/Casement Dev.app/Contents/MacOS/casementctl")
        let words = try #require(ClaudeStatusLineSetup.shellWords(edit.after!))
        #expect(words == ["/Users/me/Apps/Casement Dev.app/Contents/MacOS/casementctl", "statusline", "--", original])
        #expect(ClaudeStatusLineSetup.parseInstalled(edit.after!).original == original)
    }

    @Test func missingOrEmptyFileGetsANewObject() throws {
        for input in [nil, Data(), Data("  \n".utf8)] as [Data?] {
            let edit = try ClaudeStatusLineSetup.install(into: input, cli: "casementctl")
            #expect(text(edit.settings) == "{\n  \"statusLine\": {\n    \"type\": \"command\",\n    \"command\": \"casementctl statusline\"\n  }\n}\n")
        }
        let empty = try ClaudeStatusLineSetup.install(into: Data("{}".utf8), cli: "casementctl")
        #expect(statusLine(empty.settings)?["command"] as? String == "casementctl statusline")
        let null = try ClaudeStatusLineSetup.install(into: Data(#"{"statusLine": null}"#.utf8), cli: "casementctl")
        #expect(text(null.settings) == #"{"statusLine": {"type": "command", "command": "casementctl statusline"}}"#)
    }

    @Test func refusesWhatItCantWrap() {
        #expect(throws: ClaudeStatusLineSetup.SetupError.invalidJSON) {
            try ClaudeStatusLineSetup.install(into: Data(#"{"a": 1,}"#.utf8), cli: cli)
        }
        #expect(throws: ClaudeStatusLineSetup.SetupError.invalidJSON) {
            try ClaudeStatusLineSetup.install(into: Data("[]".utf8), cli: cli)
        }
        let odd = Data(#"{"statusLine": {"type": "static", "text": "hi"}}"#.utf8)
        #expect(throws: (any Error).self) { try ClaudeStatusLineSetup.install(into: odd, cli: cli) }
        if case .unsupported = ClaudeStatusLineSetup.status(of: odd) {} else { Issue.record("expected unsupported") }
        #expect(throws: (any Error).self) { try ClaudeStatusLineSetup.install(into: Data(#"{"statusLine": "echo hi"}"#.utf8), cli: cli) }
    }

    @Test func removeRestoresTheOriginal() throws {
        let original = #"{"statusLine": {"type": "command", "command": "~/bin/line.sh"}, "x": [1, {"y": "}"}]}"#
        let installed = try ClaudeStatusLineSetup.install(into: Data(original.utf8), cli: cli)
        let removed = try ClaudeStatusLineSetup.remove(from: installed.settings)
        #expect(text(removed.settings) == original)
        #expect(removed.after == "~/bin/line.sh")

        let plain = """
        {
          "a": 1,
          "b": 2
        }
        """
        let added = try ClaudeStatusLineSetup.install(into: Data(plain.utf8), cli: cli)
        #expect(text(try ClaudeStatusLineSetup.remove(from: added.settings).settings) == plain)

        let first = #"{"statusLine": {"type": "command", "command": "casementctl statusline"}, "a": 1}"#
        #expect(text(try ClaudeStatusLineSetup.remove(from: Data(first.utf8)).settings) == #"{"a": 1}"#)
        let only = #"{"statusLine": {"type": "command", "command": "casementctl statusline"}}"#
        #expect(text(try ClaudeStatusLineSetup.remove(from: Data(only.utf8)).settings) == "{}")

        let notOurs = Data(#"{"statusLine": {"type": "command", "command": "mine.sh"}}"#.utf8)
        #expect(!(try ClaudeStatusLineSetup.remove(from: notOurs)).changesFile)
    }

    @Test func applyKeepsABackupAndFollowsSymlinks() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("casement-claude-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appendingPathComponent("dotfiles"), withIntermediateDirectories: true)
        let real = dir.appendingPathComponent("dotfiles/settings.json")
        let link = dir.appendingPathComponent("settings.json")
        let before = Data(#"{"statusLine": {"type": "command", "command": "mine.sh"}}"#.utf8)
        try before.write(to: real)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let edit = try ClaudeStatusLineSetup.install(into: try Data(contentsOf: link), cli: cli)
        try ClaudeStatusLineSetup.apply(edit, to: link)
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == real.path)
        #expect(try Data(contentsOf: real) == edit.settings)
        #expect(try Data(contentsOf: real.appendingPathExtension("bak")) == before)
        #expect((try fm.attributesOfItem(atPath: real.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        // A plan made from an older copy is refused rather than overwriting newer edits.
        #expect(throws: ClaudeStatusLineSetup.SetupError.changedOnDisk) { try ClaudeStatusLineSetup.apply(edit, to: link) }
    }

    @Test func shellWords() {
        #expect(ClaudeStatusLineSetup.shellWords(#"a 'b c' "d \"e\"" f\ g"#) == ["a", "b c", #"d "e""#, "f g"])
        #expect(ClaudeStatusLineSetup.shellWords("'open") == nil)
        #expect(ClaudeStatusLineSetup.shellQuote("plain/path.sh") == "plain/path.sh")
        #expect(ClaudeStatusLineSetup.shellQuote("it's") == #"'it'\''s'"#)
        #expect(ClaudeStatusLineSetup.parseInstalled("casementctl statusline -- a b").original == "a b")
        #expect(ClaudeStatusLineSetup.parseInstalled("casementctl hook claude").installed == false)
    }

    /// Hook commands are quoted by the same allow-list as the status line's, so nothing the
    /// shell would act on is left bare. A list of characters to look out for used to miss these.
    @Test func hookPathsAreQuotedByTheSameAllowList() {
        #expect(ClaudeHookInstaller.quoted("/Applications/Casement.app/Contents/MacOS/casementctl")
                == "/Applications/Casement.app/Contents/MacOS/casementctl")
        for path in ["/tmp/a\nb/casementctl", "/tmp/a\tb/casementctl", "~/bin/casementctl", "/tmp/a#b/casementctl",
                     "/tmp/{a,b}/casementctl", "/tmp/[ab]/casementctl", "/tmp/a b/casementctl", "/tmp/a$b/casementctl"] {
            let quoted = ClaudeHookInstaller.quoted(path)
            #expect(quoted == ClaudeStatusLineSetup.shellQuote(path), "\(path)")
            #expect(quoted.hasPrefix("'") && quoted.hasSuffix("'"), "\(path)")
            #expect(ClaudeStatusLineSetup.shellWords(quoted) == [path], "\(path)")
        }
    }
}
