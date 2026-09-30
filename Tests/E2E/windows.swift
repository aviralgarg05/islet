// Prints the on-screen windows of a process as JSON: [{layer, x, y, width, height}]
// plus the displays, so the E2E test can check where the island panel sits.
import CoreGraphics
import Foundation

let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var windows: [[String: Any]] = []
for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    windows.append(["layer": w[kCGWindowLayer as String] as? Int ?? 0, "x": b["X"] ?? 0, "y": b["Y"] ?? 0,
                    "width": b["Width"] ?? 0, "height": b["Height"] ?? 0])
}
var count: UInt32 = 0
CGGetActiveDisplayList(0, nil, &count)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetActiveDisplayList(count, &ids, &count)
let displays = ids.map { id -> [String: Any] in
    let r = CGDisplayBounds(id)
    return ["id": id, "builtin": CGDisplayIsBuiltin(id) != 0, "x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
}
let data = try JSONSerialization.data(withJSONObject: ["windows": windows, "displays": displays])
print(String(decoding: data, as: UTF8.self))
