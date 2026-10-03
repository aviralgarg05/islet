import Foundation
import IsletCore

/// Lists and runs the user's shortcuts with macOS's own `shortcuts` tool. Nothing runs until
/// the user turns Shortcuts on and picks one; the list is read when the page opens.
public final class ShortcutsRunner {
    public static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")
    private let queue = DispatchQueue(label: "islet.shortcuts", qos: .userInitiated, attributes: .concurrent)

    public init() {}

    public static var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: tool.path) }

    public enum Failure: Error, Equatable {
        case unavailable
        case failed(String?)
    }

    /// Every shortcut, in the order the Shortcuts app keeps them. Completes on the main thread.
    public func list(completion: @escaping (Result<[ShortcutItem], Failure>) -> Void) {
        run(ShortcutsCatalog.listArguments, timeout: 20) { result in
            completion(result.map(ShortcutsCatalog.parse))
        }
    }

    /// Runs one shortcut and reports when it has finished. A shortcut can take a while (it may
    /// ask a question or wait on a network), so it has five minutes.
    public func run(_ item: ShortcutItem, completion: @escaping (Result<Void, Failure>) -> Void) {
        run(ShortcutsCatalog.runArguments(item), timeout: 300) { result in
            completion(result.map { _ in () })
        }
    }

    private func run(_ arguments: [String], timeout: TimeInterval, completion: @escaping (Result<String, Failure>) -> Void) {
        guard Self.isAvailable else {
            completion(.failure(.unavailable))
            return
        }
        queue.async {
            let process = Process()
            process.executableURL = Self.tool
            process.arguments = arguments
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            let result: Result<String, Failure>
            do {
                try process.run()
                // Read while it runs, so a long list can't fill the pipe and stall it.
                var output = Data(), errors = Data()
                let group = DispatchGroup()
                // The reads stop at the same deadline as the shortcut, so a child it leaves
                // behind holding the pipes can't keep the answer from ever arriving.
                let deadline = DispatchTime.now() + timeout
                group.enter()
                DispatchQueue.global().async {
                    output = ScriptPluginRunner.drain(out.fileHandleForReading, until: deadline)
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    errors = ScriptPluginRunner.drain(err.fileHandleForReading, until: deadline)
                    group.leave()
                }
                let timer = DispatchWorkItem { ScriptPluginRunner.halt(process) }
                DispatchQueue.global().asyncAfter(deadline: deadline, execute: timer)
                process.waitUntilExit()
                timer.cancel()
                // The shortcut has gone. A child it left behind may still hold the pipes; the
                // reads stop themselves at the deadline, so waiting on them is bounded, and the
                // grace is only for the hand-off.
                let read = group.wait(timeout: deadline + .milliseconds(250)) == .success
                if !read {
                    // The reads still own `output`, so it can't be looked at from here. Saying
                    // this succeeded with nothing in it would draw an empty list of shortcuts as
                    // though that were the answer.
                    result = .failure(.failed(nil))
                } else if process.terminationStatus == 0 {
                    result = .success(String(decoding: output, as: UTF8.self))
                } else {
                    result = .failure(.failed(ShortcutsCatalog.failureReason(String(decoding: errors, as: UTF8.self))))
                }
            } catch {
                result = .failure(.failed(nil))
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
