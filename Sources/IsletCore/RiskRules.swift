import Foundation

/// Flags tool calls that deserve a second look before "Allow". Rules only, no model: a match
/// adds friction on the approval card (a second click or a hold, no "Always"), it never blocks.
/// False positives (`echo rm -rf`) are fine; the full command is always shown.
public enum RiskRules {
    /// Reasons for a request, in the order found, without duplicates.
    public static func reasons(for r: ApprovalRequest, home: String = NSHomeDirectory()) -> [String] {
        guard case .tool = r.kind else { return [] }
        var out: [String] = []
        if r.isShell, let command = r.command {
            out += reasons(command: command, cwd: r.cwd, home: home)
        } else {
            switch r.toolName {
            case "Write", "Edit", "MultiEdit", "NotebookEdit":
                let path = r.toolInput["file_path"]?.stringValue ?? r.toolInput["notebook_path"]?.stringValue
                if let path {
                    if isSecretFile(path) { out.append(secrets) }
                    if let cwd = r.cwd, !isInside(path, cwd, home: home), !isTemporary(path, home: home) { out.append(outside) }
                }
            case "Read":
                if let path = r.toolInput["file_path"]?.stringValue, isSecretFile(path) { out.append(secrets) }
            default:
                break
            }
        }
        return unique(out)
    }

    /// One line for the card: the most serious reason, and how many more there are
    /// ("Deletes files recursively and 2 more"). The whole list goes in the card's help.
    public static func summary(_ reasons: [String]) -> String? {
        guard let first = reasons.first else { return nil }
        return reasons.count == 1 ? first : "\(first) and \(reasons.count - 1) more"
    }

    static func unique(_ reasons: [String]) -> [String] {
        var seen = Set<String>()
        return reasons.filter { seen.insert($0).inserted }
    }

    static let outside = "Writes outside the project folder"
    static let secrets = "Touches a file that often holds secrets"

    /// Reasons for a shell command line, in the order found, without duplicates.
    public static func reasons(command: String, cwd: String?, home: String = NSHomeDirectory()) -> [String] {
        var out: [String] = []
        // Whole-line patterns: pipelines and constructs a token scan can't see.
        let patterns: [(String, String)] = [
            (#":\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:"#, "Fork bomb: starts processes until the Mac stalls"),
            (#"\b(curl|wget|fetch)\b[^|;\n]*\|\s*(sudo\s+(-\S+\s+)*)?(env\s+)?(ba|z|da|k|fi)?sh\b"#, "Runs a script downloaded from the internet"),
            (#"\b(curl|wget|fetch)\b[^|;\n]*\|\s*(sudo\s+)?(python3?|perl|ruby|node)\b"#, "Runs a script downloaded from the internet"),
            (#"\b(ba|z)?sh\s+(-\S+\s+)*(<\(|["']?\$\()\s*(curl|wget)\b"#, "Runs a script downloaded from the internet"),
            (#"\beval\s+["']?\$\(\s*(curl|wget)\b"#, "Runs a script downloaded from the internet"),
            (#"(?i)\b(drop\s+(table|database|schema)|truncate\s+table)\b"#, "Drops database tables"),
        ]
        for (pattern, reason) in patterns where command.range(of: pattern, options: .regularExpression) != nil {
            out.append(reason)
        }
        for seg in segments(of: command) {
            for i in commandStarts(seg) {
                let name = (seg[i] as NSString).lastPathComponent
                if let reason = programReason(name, args: Array(seg.dropFirst(i + 1)), cwd: cwd, home: home) { out += reason }
            }
            if seg.contains(where: isSecretFile) { out.append(secrets) }
        }
        for target in redirectTargets(command) {
            if target.hasPrefix("/dev/disk") || target.hasPrefix("/dev/rdisk") || target.hasPrefix("/dev/sd") {
                out.append("Writes directly to a disk")
            } else if let cwd, isAbsoluteish(target), !isInside(target, cwd, home: home), !isTemporary(target, home: home) {
                out.append(outside)
            }
        }
        return unique(out)
    }

    /// Rules for one program occurrence and the arguments after it.
    static func programReason(_ name: String, args: [String], cwd: String?, home: String) -> [String]? {
        let flags = args.filter { $0.hasPrefix("-") }
        let shortFlags = flags.filter { !$0.hasPrefix("--") }.joined()
        func has(_ long: String) -> Bool { flags.contains { $0 == long || $0.hasPrefix(long + "=") } }
        switch name {
        case "sudo", "doas":
            return ["Runs with administrator rights"]
        case "rm":
            var r: [String] = []
            if shortFlags.contains("r") || shortFlags.contains("R") || has("--recursive") { r.append("Deletes files recursively") }
            if let cwd, args.contains(where: { !$0.hasPrefix("-") && isAbsoluteish($0) && !isInside($0, cwd, home: home) && !isTemporary($0, home: home) }) {
                r.append("Deletes files outside the project folder")
            }
            return r
        case "git":
            return gitReason(args)
        case "chmod":
            let loose = ["777", "0777", "666", "0666", "a+w", "o+w", "a+rwx", "ugo+rwx", "o+rwx", "a=rwx"]
            return args.contains(where: loose.contains) ? ["Makes files writable by everyone"] : nil
        case "dd":
            return args.contains(where: { $0.hasPrefix("of=/dev/") }) ? ["Writes directly to a disk"] : nil
        case "diskutil":
            let erase = ["eraseDisk", "eraseVolume", "zeroDisk", "randomDisk", "secureErase", "partitionDisk", "reformat"]
            return args.contains(where: erase.contains) ? ["Erases or formats a disk"] : nil
        case "shutdown", "reboot", "halt":
            return ["Shuts down or restarts the Mac"]
        case "security":
            let reads = ["find-generic-password", "find-internet-password", "dump-keychain"]
            return args.first.map(reads.contains) == true ? ["Reads passwords from the keychain"] : nil
        case "csrutil", "spctl":
            return args.contains(where: { ["disable", "--master-disable", "--global-disable"].contains($0) }) ? ["Turns off macOS security protection"] : nil
        case "find":
            return args.contains("-delete") ? ["Deletes every file find matches"] : nil
        case "crontab":
            return args.contains("-r") ? ["Removes all your scheduled jobs"] : nil
        case "npm", "pnpm", "yarn", "cargo", "twine", "gem":
            let sub = args.first { !$0.hasPrefix("-") }
            return sub == "publish" || sub == "upload" || (name == "gem" && sub == "push") ? ["Publishes a package"] : nil
        case "cp", "mv", "ln", "install", "rsync":
            // The destination is the last operand.
            let operands = args.filter { !$0.hasPrefix("-") }
            guard operands.count >= 2, let cwd, let target = operands.last, isAbsoluteish(target),
                  !isInside(target, cwd, home: home), !isTemporary(target, home: home) else { return nil }
            return [outside]
        case "terraform":
            return args.first == "destroy" ? ["Deletes cloud resources"] : nil
        case "kubectl":
            return args.first == "delete" ? ["Deletes cloud resources"] : nil
        default:
            if name.hasPrefix("mkfs") || name.hasPrefix("newfs") { return ["Erases or formats a disk"] }
            return nil
        }
    }

    static func gitReason(_ args: [String]) -> [String]? {
        // Skip global options (`-C dir`, `-c key=value`) to find the subcommand.
        var i = 0
        while i < args.count, args[i].hasPrefix("-") {
            i += ["-C", "-c", "--git-dir", "--work-tree"].contains(args[i]) ? 2 : 1
        }
        guard i < args.count else { return nil }
        let sub = args[i]
        let rest = Array(args.dropFirst(i + 1))
        let short = rest.filter { $0.hasPrefix("-") && !$0.hasPrefix("--") }.joined()
        switch sub {
        case "push":
            var r: [String] = []
            if short.contains("f") || rest.contains(where: { $0 == "--force" || $0.hasPrefix("--force-with-lease") || $0 == "--mirror" })
                || rest.contains(where: { $0.hasPrefix("+") }) {
                r.append("Force-pushes and can overwrite remote history")
            }
            if short.contains("d") || rest.contains("--delete") || rest.contains(where: { $0.hasPrefix(":") && $0.count > 1 }) {
                r.append("Deletes a remote branch")
            }
            return r
        case "reset":
            return rest.contains("--hard") ? ["Discards uncommitted changes"] : nil
        case "clean":
            return short.contains("f") || rest.contains("--force") ? ["Deletes untracked files"] : nil
        case "checkout":
            return rest.contains("--") || rest.contains(".") || short.contains("f") || rest.contains("--force") ? ["Discards uncommitted changes"] : nil
        case "restore":
            return rest.contains("--staged") && !rest.contains("--worktree") ? nil : ["Discards uncommitted changes"]
        case "branch":
            return short.contains("D") ? ["Deletes a branch even if it isn't merged"] : nil
        case "stash":
            return rest.first == "drop" || rest.first == "clear" ? ["Deletes stashed changes"] : nil
        case "filter-branch", "filter-repo":
            return ["Rewrites repository history"]
        default:
            return nil
        }
    }

    /// Wrappers that run the command after their own options, and shell keywords that come
    /// before a command (`for …; do rm -rf …`, `if …; then sudo …`).
    static let wrappers: [String: Set<String>] = [
        "sudo": ["-u", "-g", "-C", "-h", "-p", "-U"], "doas": ["-u", "-C"], "env": ["-u", "-S", "-P"],
        "xargs": ["-I", "-n", "-P", "-L", "-s", "-E", "-d", "-J"], "nice": ["-n"], "nohup": [], "time": [],
        "command": [], "exec": [], "caffeinate": ["-t", "-w"], "watch": ["-n"],
        "if": [], "then": [], "else": [], "elif": [], "do": [], "while": [], "until": [], "!": [],
    ]

    /// Positions in a simple command where a program name stands: the first word after any
    /// `VAR=value`, after wrappers such as `sudo` or `xargs`, after shell keywords such as `do`,
    /// after `sh -c` and after `find -exec`.
    static func commandStarts(_ seg: [String]) -> [Int] {
        func isAssignment(_ t: String) -> Bool { t.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil }
        var starts: [Int] = []
        var expectCommand = true
        var i = 0
        while i < seg.count {
            let t = seg[i]
            if expectCommand {
                if isAssignment(t) {
                    i += 1
                    continue
                }
                starts.append(i)
                expectCommand = false
                if let valued = wrappers[(t as NSString).lastPathComponent] {
                    i += 1
                    while i < seg.count, seg[i].hasPrefix("-") || isAssignment(seg[i]) {
                        i += valued.contains(seg[i]) ? 2 : 1
                    }
                    expectCommand = true
                    continue
                }
            } else if ["-c", "-lc", "-ic", "-exec", "-execdir", "-ok"].contains(t) {
                expectCommand = true
            }
            i += 1
        }
        return starts
    }

    /// Splits a command line into simple commands of words. Quotes are dropped rather than
    /// honoured, so commands inside `bash -c '…'` or `$(…)` are seen too.
    static func segments(of command: String) -> [[String]] {
        var segments: [[String]] = [[]]
        var word = ""
        func endWord() {
            if !word.isEmpty { segments[segments.count - 1].append(word) }
            word = ""
        }
        func endSegment() {
            endWord()
            if !(segments.last?.isEmpty ?? true) { segments.append([]) }
        }
        for ch in command {
            switch ch {
            case ";", "&", "|", "\n", "(", ")", "{", "}", "`":
                endSegment()
            case " ", "\t", "\r":
                endWord()
            case "'", "\"", "\\":
                continue
            default:
                word.append(ch)
            }
        }
        endSegment()
        return segments.filter { !$0.isEmpty }
    }

    /// Files written by `>`, `>>` and `tee`.
    static func redirectTargets(_ command: String) -> [String] {
        var targets: [String] = []
        let ns = command as NSString
        if let re = try? NSRegularExpression(pattern: #"(?<![0-9&<>])>{1,2}\|?\s*([^\s;&|<>()]+)"#) {
            for m in re.matches(in: command, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges > 1 {
                targets.append(ns.substring(with: m.range(at: 1)))
            }
        }
        for seg in segments(of: command) {
            for (i, token) in seg.enumerated() where (token as NSString).lastPathComponent == "tee" {
                targets += seg.dropFirst(i + 1).filter { !$0.hasPrefix("-") }
            }
        }
        return targets.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) }
            .filter { !$0.isEmpty && !$0.hasPrefix("&") && !["/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty"].contains($0) }
    }

    static func isAbsoluteish(_ path: String) -> Bool {
        path.hasPrefix("/") || path.hasPrefix("~") || path.hasPrefix("$HOME") || path.hasPrefix("${HOME}") || path.hasPrefix("..")
    }

    static func expand(_ path: String, cwd: String, home: String) -> String {
        var p = path
        for prefix in ["$HOME", "${HOME}", "~"] where p == prefix || p.hasPrefix(prefix + "/") {
            p = home + p.dropFirst(prefix.count)
            break
        }
        if !p.hasPrefix("/") { p = (cwd as NSString).appendingPathComponent(p) }
        return (p as NSString).standardizingPath
    }

    static func isInside(_ path: String, _ cwd: String, home: String) -> Bool {
        let root = (cwd as NSString).standardizingPath
        let p = expand(path, cwd: root, home: home)
        return p == root || p.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    static func isTemporary(_ path: String, home: String) -> Bool {
        let p = expand(path, cwd: "/", home: home)
        return ["/tmp", "/private/tmp", "/var/folders", "/private/var/folders"].contains { p == $0 || p.hasPrefix($0 + "/") }
    }

    /// Files that usually hold keys or passwords.
    static func isSecretFile(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if name == ".env" || (name.hasPrefix(".env.") && !["example", "sample", "template", "dist"].contains(name.dropFirst(5).lowercased())) { return true }
        if ["id_rsa", "id_ed25519", "id_ecdsa", "id_dsa", ".netrc", ".npmrc", ".pypirc", "credentials"].contains(name) { return true }
        if name.hasSuffix(".pem") || name.hasSuffix(".p12") || name.hasSuffix(".key") { return true }
        return ["/.ssh/", "/.aws/", "/.gnupg/", "/Keychains/"].contains { path.contains($0) } || path.hasPrefix(".ssh/") || path.hasPrefix("~/.ssh")
    }
}
