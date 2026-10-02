import AppKit
import Foundation
import IsletCore
import os

/// Persists the file shelf and performs file actions (AirDrop, share, reveal, open).
///
/// Nothing here touches a file on another volume from the main thread: a network share that
/// has stopped answering could otherwise hold up launch or the island. Files on the startup
/// disk are checked at once; the rest are checked in the background (`checkVolumes`), and
/// one whose volume doesn't answer in time is dimmed, not dropped.
public final class ShelfService {
    public private(set) var shelf: Shelf
    public var onChange: ((Shelf) -> Void)?
    /// Items that can't be opened now (shown dimmed): their volume isn't mounted, or didn't
    /// answer within `volumeTimeout`.
    public private(set) var unavailable: Set<String> = []
    public var onAvailability: ((Set<String>) -> Void)?
    private let storeURL: URL
    /// False when an unreadable shelf.json couldn't be moved aside: then it is left alone.
    private let canSave: Bool
    private let exists: @Sendable (String) -> Bool
    private let volumeTimeout: TimeInterval
    private var checkGeneration = 0
    private var answeredGeneration = 0
    private var mountObservers: [NSObjectProtocol] = []

    /// - Parameters:
    ///   - exists: whether a path exists (tests pass a slow one).
    ///   - volumeTimeout: how long the files on other volumes may take before they show dimmed.
    public init(storeURL: URL = IsletPaths.supportDirectory.appendingPathComponent("shelf.json"),
                exists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                volumeTimeout: TimeInterval = 2) {
        self.storeURL = storeURL
        self.exists = exists
        self.volumeTimeout = volumeTimeout
        // A shelf.json that doesn't parse goes to shelf.json.corrupt before the shelf starts empty.
        let restored = JSONStore.start(storeURL) { JSONStore.read(Shelf.self, from: $0) }
        shelf = restored.value ?? Shelf()
        canSave = restored.canSave
        if let moved = restored.setAside { Log.files.error("shelf.json couldn't be read; kept as \(moved.lastPathComponent, privacy: .public)") }
        resolveBookmarks(onStartupDisk: true)
        shelf.prune { path in Shelf.volume(of: path) != nil || exists(path) }
        checkVolumes()
        // A disk or share coming or going changes what can be opened.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            mountObservers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.checkVolumes() })
        }
    }

    deinit {
        mountObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    public func add(urls: [URL]) {
        let paths = urls.filter(\.isFileURL).map(\.path)
        guard !paths.isEmpty else { return }
        let added = shelf.add(paths: paths, now: Date())
        save()
        // Bookmarks (so moved or renamed files stay on the shelf) are made in the background:
        // making one reads the file, which may be on a share that is slow to answer.
        guard !added.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let marks = added.map { ($0, try? URL(fileURLWithPath: $0).bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)) }
            DispatchQueue.main.async {
                guard let self else { return }
                for (path, data) in marks { self.shelf.setBookmark(data, forPath: path) }
                self.save()
            }
        }
    }

    public func remove(id: String) {
        shelf.remove(id: id)
        save()
    }

    public func removeAll() {
        shelf.removeAll()
        save()
    }

    /// Takes off the shelf what has been there `keepFor` seconds or more (0 keeps everything).
    /// The files themselves stay where they are.
    public func expire(now: Date, keepFor: TimeInterval) {
        guard !shelf.expire(now: now, keepFor: keepFor).isEmpty else { return }
        save()
    }

    public func urls(ids: [String]? = nil) -> [URL] {
        shelf.items.filter { ids == nil || ids!.contains($0.id) }.map { URL(fileURLWithPath: $0.path) }
    }

    /// Look at the files on other volumes in the background: drop ones whose file is gone,
    /// dim ones whose volume isn't there. A volume that doesn't answer within `volumeTimeout`
    /// dims its files until it does.
    public func checkVolumes() {
        let items = shelf.items.filter { !Shelf.isOnStartupDisk($0) }
        checkGeneration += 1
        let generation = checkGeneration
        guard !items.isEmpty else {
            setUnavailable([])
            return
        }
        let exists = self.exists
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let results = items.map { item -> (id: String, path: String?, outcome: ShelfCheck) in
                let moved = Self.resolved(item)
                return (item.id, moved, ShelfCheck.check(path: moved ?? item.path, exists: exists))
            }
            DispatchQueue.main.async { self?.finishCheck(results, generation: generation) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + volumeTimeout) { [weak self] in
            guard let self, self.checkGeneration == generation, self.answeredGeneration != generation else { return }
            self.setUnavailable(self.unavailable.union(items.map(\.id)))
        }
    }

    private func finishCheck(_ results: [(id: String, path: String?, outcome: ShelfCheck)], generation: Int) {
        guard generation == checkGeneration else { return }
        answeredGeneration = generation
        var changed = false
        for r in results {
            if let path = r.path {
                shelf.updatePath(id: r.id, to: path)
                changed = true
            }
            if r.outcome == .gone {
                shelf.remove(id: r.id)
                changed = true
            }
        }
        if changed { save() }
        setUnavailable(Set(results.filter { $0.outcome == .unreachable }.map(\.id)))
    }

    private func setUnavailable(_ ids: Set<String>) {
        guard ids != unavailable else { return }
        unavailable = ids
        onAvailability?(ids)
    }

    /// Where a bookmark says a moved or renamed file is now, or nil when it hasn't moved. Never
    /// mounts a volume.
    private static func resolved(_ item: ShelfItem) -> String? {
        guard let data = item.bookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil,
                                 bookmarkDataIsStale: &stale), url.path != item.path else { return nil }
        return url.path
    }

    /// Follow bookmarks so moved or renamed files stay on the shelf: at launch, those on the
    /// startup disk (the rest in `checkVolumes`).
    private func resolveBookmarks(onStartupDisk: Bool) {
        for item in shelf.items where Shelf.isOnStartupDisk(item) == onStartupDisk {
            if let path = Self.resolved(item) { shelf.updatePath(id: item.id, to: path) }
        }
    }

    private func save() {
        if canSave {
            try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(shelf) { try? data.write(to: storeURL, options: .atomic) }
        }
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
