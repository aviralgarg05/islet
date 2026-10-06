import AppKit
import CasementCore
import CasementSystem
import Observation

/// The stickers the GIF look can show: Casement's own (in the app's Resources/Stickers) and the
/// user's (`StickerStore`, in the support folder). It reads the folder only when Settings or
/// the island asks, decodes frames at the size they are drawn, and shares them between the
/// displays showing the same sticker only while something shows it: once the last view lets
/// go, the frames are freed.
@MainActor
@Observable
final class StickerLibrary {
    @ObservationIgnored let store: StickerStore
    @ObservationIgnored private let builtInFolder: URL?
    /// The user's stickers, oldest first. Read on first use.
    private(set) var custom: [String] = []
    @ObservationIgnored private var loaded = false
    /// A plain message about the last file that couldn't be added, until the next try.
    var problem: String?
    /// An import is under way (a drop can arrive while another is still being read).
    var adding: Bool { importing > 0 }
    private var importing = 0
    @ObservationIgnored private var cache: [String: Weak] = [:]

    private final class Weak {
        weak var animation: StickerAnimation?
        init(_ a: StickerAnimation) { animation = a }
    }

    init(folder: URL, builtIns: URL? = StickerLibrary.builtInFolder()) {
        store = StickerStore(directory: folder)
        builtInFolder = builtIns
    }

    /// The app's own stickers: inside the bundle, or the repository's Resources/Stickers in a
    /// development build.
    nonisolated static func builtInFolder() -> URL? {
        var dirs: [URL] = []
        if let res = Bundle.main.resourceURL, Bundle.main.bundleIdentifier != nil {
            dirs.append(res.appendingPathComponent("Stickers"))
        }
        #if DEBUG
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        // swift build: .build/<triple>/debug/Casement, or .build/debug/Casement
        dirs.append(exe.appendingPathComponent("../../../Resources/Stickers").standardizedFileURL)
        dirs.append(exe.appendingPathComponent("../../Resources/Stickers").standardizedFileURL)
        // This file's place in the repository.
        dirs.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Stickers").standardizedFileURL)
        #endif
        return dirs.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent(BuiltInSticker.cat.fileName).path) }
    }

    func loadIfNeeded() {
        guard !loaded else { return }
        reload()
    }

    func reload() {
        loaded = true
        custom = store.ids()
    }

    /// Where a sticker's file is, or nil if it's gone (a removed custom one).
    func url(for choice: StickerChoice) -> URL? {
        switch choice {
        case .builtIn(let b): return builtInFolder?.appendingPathComponent(b.fileName)
        case .custom(let id): return store.url(for: id)
        }
    }

    /// The sticker to show for these settings: the chosen one, or the cat if that has gone.
    func resolved(_ s: StickerSettings) -> StickerChoice {
        s.shown { store.url(for: $0) != nil }
    }

    // MARK: Frames

    /// Frames already decoded for this sticker at this size, if something still holds them.
    func cached(_ choice: StickerChoice, pixel: Int) -> StickerAnimation? {
        cache[key(choice, pixel)]?.animation
    }

    /// Decodes the sticker's frames off the main thread (once per size while in use).
    func frames(_ choice: StickerChoice, pixel: Int) async -> StickerAnimation? {
        if let a = cached(choice, pixel: pixel) { return a }
        guard let url = url(for: choice) else { return nil }
        let animation = await Task.detached(priority: .userInitiated) {
            StickerDecoder.decode(url: url, maxPixel: pixel)
        }.value
        if let animation { cache[key(choice, pixel)] = Weak(animation) }
        cache = cache.filter { $0.value.animation != nil }
        return animation
    }

    /// The first frame, for gallery tiles and snapshots: decoded once and kept (a few small
    /// pictures), so redrawing Settings doesn't read the files again.
    func still(_ choice: StickerChoice, pixel: Int) -> CGImage? {
        let k = key(choice, pixel)
        if let image = stills[k] { return image }
        if let a = cached(choice, pixel: pixel) { return a.frames.first }
        guard let url = url(for: choice), let image = StickerDecoder.firstFrame(url: url, maxPixel: pixel) else { return nil }
        stills[k] = image
        return image
    }
    @ObservationIgnored private var stills: [String: CGImage] = [:]

    /// Width over height, read from the file's header (no frames decoded); built-ins are square.
    func aspect(_ choice: StickerChoice) -> CGFloat {
        if case .builtIn = choice { return 1 }
        if let a = aspects[choice.id] { return a }
        let a = url(for: choice).flatMap(StickerDecoder.aspect(url:)) ?? 1
        aspects[choice.id] = a
        return a
    }
    @ObservationIgnored private var aspects: [String: CGFloat] = [:]

    /// All the frames at once (snapshots).
    func decodedNow(_ choice: StickerChoice, pixel: Int) -> StickerAnimation? {
        if let a = cached(choice, pixel: pixel) { return a }
        guard let url = url(for: choice), let a = StickerDecoder.decode(url: url, maxPixel: pixel) else { return nil }
        cache[key(choice, pixel)] = Weak(a)
        return a
    }

    private func key(_ choice: StickerChoice, _ pixel: Int) -> String { "\(choice.id)@\(pixel)" }

    /// Frames a view has just let go, kept until the main queue's next turn: a view SwiftUI
    /// puts in the old one's place in the same update finds them in the cache.
    func linger(_ animation: StickerAnimation) {
        lingering.append(animation)
        guard lingering.count == 1 else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.lingering.removeAll() }
        }
    }
    @ObservationIgnored private var lingering: [StickerAnimation] = []

    // MARK: The user's stickers

    /// Copies pictures in as stickers, one after another, and returns the last one added.
    /// Problems show in `problem`, in plain words.
    @discardableResult
    func add(_ urls: [URL]) async -> String? {
        loadIfNeeded()
        problem = nil
        importing += 1
        defer { importing -= 1 }
        var last: String?
        for url in urls {
            let store = self.store
            let result: Result<String, StickerImportError> = await Task.detached(priority: .userInitiated) {
                do { return .success(try store.add(from: url)) } catch let e as StickerImportError { return .failure(e) } catch {
                    return .failure(.unreadable)
                }
            }.value
            switch result {
            case .success(let id): last = id
            case .failure(let e): problem = e.message
            }
        }
        reload()
        return last
    }

    func remove(_ id: String) {
        store.remove(id)
        let prefix = StickerChoice.custom(id).id + "@"
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
        stills = stills.filter { !$0.key.hasPrefix(prefix) }
        reload()
    }

    var isFull: Bool { custom.count >= StickerLimits.maxCustom }
}
