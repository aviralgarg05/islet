import Foundation
import IsletCore

/// `isletctl debug menubar [--watch]`: what Islet sees in the menu bar, for checking how a Live
/// Activity looks to it. With --watch it prints a timestamped snapshot whenever the items change,
/// until Ctrl-C, so you can start an activity and capture it.
func debugMenuBar(watch: Bool) async throws -> Int32 {
    let client = try Client.discover()
    let data = try expectOK(try await client.send("GET", "/v1/debug/menubar"))
    guard watch else {
        print(String(decoding: data, as: UTF8.self))
        return 0
    }
    var last = Data()
    let formatter = ISO8601DateFormatter()
    FileHandle.standardError.write(Data("Watching the menu bar; press Ctrl-C to stop.\n".utf8))
    while true {
        let (status, body) = try await client.send("GET", "/v1/debug/menubar")
        if status == 200, body != last {
            last = body
            print("--- \(formatter.string(from: Date()))")
            if let items = try? APIJSON.decoder.decode([MenuBarItemInfo].self, from: body) {
                for item in items where item.kind != .thirdParty {
                    let text = item.allText.joined(separator: " | ")
                    let flags = [item.hidden ? "hidden" : nil, item.kind?.rawValue].compactMap { $0 }.joined(separator: ", ")
                    print("  x=\(Int(item.x)) w=\(Int(item.width)) [\(flags)] \(item.identifier ?? "-") \(text)")
                }
            } else {
                print(String(decoding: body, as: UTF8.self))
            }
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }
}
