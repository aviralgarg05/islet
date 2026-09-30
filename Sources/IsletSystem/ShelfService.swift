import AppKit
import Foundation
import IsletCore

/// Persists the file shelf and performs file actions (AirDrop, share, reveal, open).
public final class ShelfService {
    public private(set) var shelf: Shelf
    public var onChange: ((Shelf) -> Void)?
    private let storeURL: URL

    public init(storeURL: URL = IsletPaths.supportDirectory.appendingPathComponent("shelf.json")) {
        self.storeURL = storeURL
        if let data = try? Data(contentsOf: storeURL), let s = try? JSONDecoder().decode(Shelf.self, from: data) {
            shelf = s
        } else {
            shelf = Shelf()
        }
        resolveBookmarks()
        shelf.prune { FileManager.default.fileExists(atPath: $0) }
    }

    public func add(urls: [URL]) {
        let paths = urls.filter(\.isFileURL).map(\.path)
        guard !paths.isEmpty else { return }
        shelf.add(paths: paths, now: Date()) { path in
            try? URL(fileURLWithPath: path).bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        save()
    }

    public func remove(id: String) {
        shelf.remove(id: id)
        save()
    }

    public func removeAll() {
        shelf.removeAll()
        save()
    }

    public func urls(ids: [String]? = nil) -> [URL] {
        shelf.items.filter { ids == nil || ids!.contains($0.id) }.map { URL(fileURLWithPath: $0.path) }
    }

    /// Follow bookmarks so moved or renamed files stay on the shelf. Never mounts a volume: an
    /// item on a disconnected disk or share must not hold up launch.
    private func resolveBookmarks() {
        for item in shelf.items {
            guard let data = item.bookmark else { continue }
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
               url.path != item.path {
                shelf.updatePath(id: item.id, to: url.path)
            }
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(shelf) { try? data.write(to: storeURL, options: .atomic) }
        onChange?(shelf)
    }

    // MARK: Actions

    @discardableResult
    public static func airDrop(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else { return false }
        service.perform(withItems: urls)
        return true
    }

    public static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    public static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
