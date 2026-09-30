import Foundation
import IsletCore

/// `isletctl statusline [-- <command…>]`: Claude Code's status-line command.
///
/// Records the plan usage Claude passes on stdin in the usage folder (only when it changed),
/// then runs the user's own status line with the same input and passes its output through.
/// A single argument after `--` is a shell command line (that's how Claude stores it); several
/// arguments run directly, without a shell. Never contacts the network or the app.
func runStatusLine(_ original: [String]) -> Int32 {
    // A status line that exits early must not kill us through a broken pipe.
    signal(SIGPIPE, SIG_IGN)
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let recorded = StatusLineBridge.record(input, in: AgentUsageStore.directory)

    guard !original.isEmpty else {
        if let usage = recorded.usage { print(StatusLineBridge.defaultLine(usage)) }
        return 0
    }

    let p = Process()
    if original.count == 1 {
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", original[0]]
    } else {
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = original
    }
    let stdin = Pipe()
    p.standardInput = stdin
    p.standardOutput = FileHandle.standardOutput
    p.standardError = FileHandle.standardError
    do {
        try p.run()
    } catch {
        FileHandle.standardError.write(Data("isletctl statusline: \(error)\n".utf8))
        return 127
    }
    let writer = stdin.fileHandleForWriting
    DispatchQueue.global(qos: .userInitiated).async {
        try? writer.write(contentsOf: input)
        try? writer.close()
    }
    p.waitUntilExit()
    return p.terminationStatus
}
