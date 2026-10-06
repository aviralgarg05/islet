import Foundation

/// Splits an agent's plan (Markdown) into blocks the island can lay out: headings, list items,
/// code and paragraphs. Inline markup (`**bold**`, `code`) stays in the text for the view.
public enum PlanMarkdown {
    public enum Block: Equatable, Sendable {
        case heading(String, level: Int)
        /// A bullet or numbered item; `marker` is "•" or "3.".
        case item(String, marker: String, depth: Int)
        case code(String)
        case paragraph(String)
    }

    public static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var code: [String]?
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code {
                    out.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(raw)
                continue
            }
            guard !line.isEmpty, line != "---", line != "***" else { continue }
            let depth = raw.prefix(while: { $0 == " " }).count / 2
            if let hashes = line.firstIndex(where: { $0 != "#" }), hashes != line.startIndex, line[hashes] == " " {
                let level = line.distance(from: line.startIndex, to: hashes)
                out.append(.heading(String(line[hashes...]).trimmingCharacters(in: .whitespaces), level: min(level, 3)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                var item = String(line.dropFirst(2))
                if item.hasPrefix("[ ] ") { item = "☐ " + item.dropFirst(4) }
                if item.hasPrefix("[x] ") || item.hasPrefix("[X] ") { item = "☑ " + item.dropFirst(4) }
                out.append(.item(item, marker: "•", depth: depth))
            } else if let dot = line.firstIndex(where: { !$0.isNumber }), dot != line.startIndex,
                      line[dot] == "." || line[dot] == ")", line[line.index(after: dot)...].hasPrefix(" ") {
                out.append(.item(String(line[line.index(dot, offsetBy: 2)...]), marker: String(line[..<dot]) + ".", depth: depth))
            } else {
                out.append(.paragraph(line))
            }
        }
        if let lines = code { out.append(.code(lines.joined(separator: "\n"))) }
        return out
    }
}
