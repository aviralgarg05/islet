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
                group.enter()
                DispatchQueue.global().async {
                    output = out.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    errors = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                process.waitUntilExit()
                timer.cancel()
                group.wait()
                if process.terminationStatus == 0 {
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
