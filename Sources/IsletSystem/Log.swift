import Foundation
import os

/// Unified logging, one category per area, so Console (or `log stream` with Islet's subsystem)
/// shows what went wrong where: a card that ran out of time, a helper that stopped, a file that
/// couldn't be read. macOS keeps the log's size in check; Islet writes no log file of its own.
/// Nothing a user typed, copied or was sent goes in.
public enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "Islet"
    public static let approvals = Logger(subsystem: subsystem, category: "approvals")
    public static let media = Logger(subsystem: subsystem, category: "media")
    public static let files = Logger(subsystem: subsystem, category: "files")
    public static let api = Logger(subsystem: subsystem, category: "api")
}
