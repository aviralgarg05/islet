import Foundation

/// "Send feedback": the project's issue form on GitHub, opened in the browser with the Islet
/// and macOS versions filled in. Nothing is sent from Islet; you read the form, write the rest
/// and submit it yourself, or close the tab.
public enum Feedback {
    public enum Kind: String, CaseIterable, Sendable {
        case bug, idea

        public var title: String {
            switch self {
            case .bug: return "Report a problem…"
            case .idea: return "Suggest an idea…"
            }
        }

        /// The issue form in `.github/ISSUE_TEMPLATE`.
        var template: String {
            switch self {
            case .bug: return "bug_report.yml"
            case .idea: return "feature_request.yml"
            }
        }
    }

    static let newIssue = "https://github.com/aviralgarg05/islet/issues/new"

    /// The form's address. The version fields are filled in by their ids in the form
    /// (`islet-version`, `macos-version`); nothing else about the Mac is added.
    public static func url(_ kind: Kind, version: String, macOS: String) -> URL {
        var c = URLComponents(string: newIssue)!
        c.queryItems = [
            URLQueryItem(name: "template", value: kind.template),
            URLQueryItem(name: "islet-version", value: clean(version)),
            URLQueryItem(name: "macos-version", value: clean(macOS)),
        ]
        return c.url!
    }

    /// "macOS 27.0.1 (26A123)" from the system's version, as About This Mac writes it.
    public static func macOSVersion(_ v: OperatingSystemVersion, build: String?) -> String {
        var s = "macOS \(v.majorVersion).\(v.minorVersion)"
        if v.patchVersion > 0 { s += ".\(v.patchVersion)" }
        if let build, !build.isEmpty { s += " (\(build))" }
        return s
    }

    /// One short line: a version never needs more.
    static func clean(_ text: String) -> String {
        String(text.filter { !$0.isNewline }.prefix(64)).trimmingCharacters(in: .whitespaces)
    }
}
