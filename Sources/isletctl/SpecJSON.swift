import Foundation
import IsletCore

/// `isletctl set <id> --json FILE|-`: a full activity from a file or stdin, for the template
/// fields that have no flag of their own (teams, flight, route, metrics…). Flags given on the
/// command line win over the file; the file's `source` wins over the default "cli".
func mergedSpecJSON(file path: String, flags: ActivitySpec, keepSource: Bool) throws -> Data {
    let data: Data
    if path == "-" {
        data = FileHandle.standardInput.readDataToEndOfFile()
    } else {
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        } catch {
            throw CLIError("--json: can't read \(path)")
        }
    }
    // Decode first so mistakes are reported here, with the field name.
    do {
        _ = try APIJSON.decoder.decode(ActivitySpec.self, from: data)
    } catch let DecodingError.typeMismatch(_, c), let DecodingError.valueNotFound(_, c), let DecodingError.dataCorrupted(c) {
        let field = c.codingPath.map(\.stringValue).joined(separator: ".")
        throw CLIError("--json: \(field.isEmpty ? "" : "'\(field)': ")\(c.debugDescription)")
    } catch {
        throw CLIError("--json: \(error)")
    }
    guard var base = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CLIError("--json must contain a JSON object")
    }
    var overrides = try JSONSerialization.jsonObject(with: APIJSON.encoder.encode(flags)) as? [String: Any] ?? [:]
    if !keepSource, base["source"] != nil { overrides["source"] = nil }
    base.merge(overrides) { _, flag in flag }
    return try JSONSerialization.data(withJSONObject: base, options: [.sortedKeys])
}
