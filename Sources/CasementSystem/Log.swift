import Foundation
import os

/// Unified logging, one category per area, so Console (or `log stream` with Casement's subsystem)
/// shows what went wrong where: a card that ran out of time, a helper that stopped, a file that
/// couldn't be read. macOS keeps the log's size in check; Casement writes no log file of its own.
/// Nothing a user typed, copied or was sent goes in.
public enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "Casement"
    public static let approvals = Logger(subsystem: subsystem, category: "approvals")
    public static let media = Logger(subsystem: subsystem, category: "media")
    public static let files = Logger(subsystem: subsystem, category: "files")
    public static let api = Logger(subsystem: subsystem, category: "api")
    /// Ask's failures in full (a status, an exit code), which the island puts in plain words.
    public static let ask = Logger(subsystem: subsystem, category: "ask")
}
