import Foundation
import IsletCore

/// `isletctl hook <agent> [--wait N] [JSON]`.
///
/// Hooks must never break the agent that runs them: any failure (Islet not running, API off,
/// timeout) exits 0 with nothing on stdout, and the agent carries on as if no hook had run.
/// With `--wait`, events that ask for a decision block until it's answered in the notch (or
/// N seconds pass) and the answer is printed for the agent. Everything else is sent and
/// forgotten within 1.5 s.
func forwardHook(provider: String, payload: Data, wait: Int?) async {
    do {
        let client = try Client.discover()
        if let wait, ApprovalRequest.parse(provider: provider, payload: payload) != nil {
            let seconds = min(max(wait, 1), APIRouter.maxApprovalWait)
            let (status, data) = try await client.send("POST", "/v1/hooks/\(provider)?wait=\(seconds)",
                                                       json: addingTerminal(to: payload), timeout: TimeInterval(seconds + 15))
            // Print only a well-formed decision; anything else means "no decision".
            if status == 200, JSONValue.parse(data)?.objectValue != nil {
                FileHandle.standardOutput.write(data + Data("\n".utf8))
            }
        } else {
            _ = try await client.send("POST", "/v1/hooks/\(provider)", json: payload, timeout: 1.5)
        }
    } catch {
        if ProcessInfo.processInfo.environment["ISLET_DEBUG"] != nil {
            FileHandle.standardError.write(Data("isletctl hook: \(error)\n".utf8))
        }
    }
}

/// Adds `_terminal` (where the agent runs) so the card can bring that terminal back.
func addingTerminal(to payload: Data) -> Data {
    guard var obj = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else { return payload }
    let context = TerminalContext.from(environment: ProcessInfo.processInfo.environment, tty: parentTTY())
    guard !context.isEmpty else { return payload }
    obj["_terminal"] = context.values
    return (try? JSONSerialization.data(withJSONObject: obj)) ?? payload
}

/// The terminal of the process that ran the hook (stdin is the payload pipe, so ours can't be used).
func parentTTY() -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-o", "tty=", "-p", String(getppid())]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    p.standardInput = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let tty = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return tty.isEmpty ? nil : tty
}
