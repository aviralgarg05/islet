import Foundation
import IsletCore

/// Watches a downloads folder for in-progress browser downloads (`.crdownload`, `.download`,
/// `.part`…) and reports progress and completion. Event-driven on folder changes; while a
/// download is growing it also checks once a second (file growth doesn't change the folder),
/// less often once it stops growing, and not at all after ten quiet minutes.
public final class DownloadsWatcher {
    public var onEvent: ((DownloadTracker.Event) -> Void)?
    public let directory: URL
    private var tracker = DownloadTracker()
    private var source: DispatchSourceFileSystemObject?
    /// A standby watch on the folder that holds Downloads, kept only while there is nothing at
    /// the path. Downloads moved to the Trash leaves nothing to watch, so the event saying it is
    /// back can only arrive on its parent; once it is back, this is let go of again.
    private var parent: DispatchSourceFileSystemObject?
    private var ticker: Timer?

    public init(directory: URL = IsletPaths.home.appendingPathComponent("Downloads")) {
        self.directory = directory
    }

    deinit { stop() }

    public func start() {
        guard source == nil else { return }
        let fd = open(directory.path, O_EVTONLY)
        // Nothing at the path: stand by on the folder that holds it until it comes back.
        guard fd >= 0 else { return watchParent() }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            // The folder itself was replaced or restored (a restore from the Trash, a different
            // volume): follow the path, not the folder that has gone, as the settings and usage
            // watchers do. Without this, download pills stopped for the rest of the session.
            if !(self.source?.data ?? []).isDisjoint(with: [.delete, .rename]) { return self.rearm() }
            self.scan()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        // Watched directly now, so the standby on its parent has nothing left to do.
        parent?.cancel()
        parent = nil
        scan()
    }

    /// Watch the path again. `start()` ends with a scan of its own; a path with no folder at it
    /// still gets one, so a download that has gone is reported, and `start()` stands by on the
    /// parent so the path is picked up again when the folder comes back.
    private func rearm() {
        source?.cancel()
        source = nil
        start()
        if source == nil { scan() }
    }

    /// Watch the folder Downloads sits in, so a folder deleted and then restored is followed.
    /// Nothing polls: the restore is a write to the parent, and that is what wakes this. Only
    /// while the folder is away, so an ordinary Mac has no second watch at all.
    private func watchParent() {
        guard parent == nil else { return }
        let fd = open(directory.deletingLastPathComponent().path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self, self.source == nil else { return }
            self.start()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        parent = src
    }

    public func stop() {
        source?.cancel()
        source = nil
        parent?.cancel()
        parent = nil
        ticker?.invalidate()
        ticker = nil
    }

    /// Size of a partial download. Safari's `.download` bundle records the expected total.
    static func partial(at url: URL) -> PartialDownload? {
        let fm = FileManager.default
        let name = url.lastPathComponent
        guard PartialDownload.isPartial(name) else { return nil }
        if name.hasSuffix(".download") {
            let info = url.appendingPathComponent("Info.plist")
            if let data = try? Data(contentsOf: info),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                let done = (plist["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
                let total = (plist["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
                return PartialDownload(fileName: name, bytes: done, totalBytes: (total ?? 0) > 0 ? total : nil)
            }
            let size = (try? fm.subpathsOfDirectory(atPath: url.path))?.reduce(Int64(0)) { sum, sub in
                sum + ((try? fm.attributesOfItem(atPath: url.appendingPathComponent(sub).path)[.size] as? NSNumber)?.int64Value ?? 0)
            } ?? 0
            return PartialDownload(fileName: name, bytes: size)
        }
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return PartialDownload(fileName: name, bytes: size)
    }

    public func scan() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let partials = names.filter(PartialDownload.isPartial).compactMap { Self.partial(at: directory.appendingPathComponent($0)) }
        let now = Date()
        for e in tracker.scan(partials: partials, existing: Set(names), now: now) { onEvent?(e) }
        // File growth doesn't touch the folder, so look again while something is downloading;
        // back off once nothing has grown for a while and stop after that (folder events remain).
        let interval = tracker.recheckInterval(now: now)
        if interval != ticker?.timeInterval {
            ticker?.invalidate()
            ticker = nil
            if let interval {
                let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.scan() }
                t.tolerance = interval * 0.3
                RunLoop.main.add(t, forMode: .common)
                ticker = t
            }
        }
    }
}

/// "Welcome back" when the screen unlocks (the long-standing distributed notification).
public final class UnlockMonitor {
    public var onUnlock: (() -> Void)?
    public var onLock: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    public init() {}
    deinit { stop() }

    public func start() {
        guard observers.isEmpty else { return }
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.onUnlock?()
        })
        observers.append(dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.onLock?()
        })
    }

    public func stop() {
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers.removeAll()
    }
}
