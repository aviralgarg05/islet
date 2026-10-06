import CoreGraphics
import Foundation
import ImageIO
import CasementCore
import UniformTypeIdentifiers

/// A sticker's frames, decoded once at the size they are drawn, with each frame's time.
public final class StickerAnimation: @unchecked Sendable {
    public let frames: [CGImage]
    public let delays: [Double]

    public init(frames: [CGImage], delays: [Double]) {
        self.frames = frames
        self.delays = delays
    }

    public var duration: Double { StickerTiming.duration(delays) }
    public var isAnimated: Bool { frames.count > 1 && duration > 0 }
    /// Width over height of the first frame.
    public var aspect: CGFloat {
        guard let f = frames.first, f.height > 0 else { return 1 }
        return CGFloat(f.width) / CGFloat(f.height)
    }
}

/// Reads animated pictures with ImageIO: GIF, animated PNG, WebP and HEIC sequences.
public enum StickerDecoder {
    /// The picture types a sticker may come from.
    public static let types: [UTType] = [.gif, .png, .webP] + [UTType("public.heics")].compactMap { $0 }

    /// A file's picture, its frames scaled so the longer side is at most `maxPixel`, keeping
    /// at most `maxFrames` frames spread over the loop. Nil for anything ImageIO can't read.
    public static func decode(url: URL, maxPixel: Int, maxFrames: Int = StickerLimits.maxFrames) -> StickerAnimation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return decode(source, maxPixel: maxPixel, maxFrames: maxFrames)
    }

    public static func decode(data: Data, maxPixel: Int, maxFrames: Int = StickerLimits.maxFrames) -> StickerAnimation? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return decode(source, maxPixel: maxPixel, maxFrames: maxFrames)
    }

    /// The first frame alone (gallery tiles and still pictures).
    public static func firstFrame(url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return frame(source, at: 0, maxPixel: maxPixel)
    }

    /// Width over height from the file's header, without decoding a frame.
    public static func aspect(url: URL) -> CGFloat? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, w > 0, h > 0 else { return nil }
        return CGFloat(w / h)
    }

    static func decode(_ source: CGImageSource, maxPixel: Int, maxFrames: Int) -> StickerAnimation? {
        let count = CGImageSourceGetCount(source)
        guard count > 0, maxPixel > 0 else { return nil }
        let delays = StickerTiming.delays((0..<count).map { delay(source, at: $0) })
        let kept = StickerTiming.kept(count: count, limit: maxFrames)
        var frames: [CGImage] = []
        frames.reserveCapacity(kept.count)
        for i in kept {
            guard let image = frame(source, at: i, maxPixel: maxPixel) else { return nil }
            frames.append(image)
        }
        return StickerAnimation(frames: frames, delays: StickerTiming.delays(delays, keeping: kept))
    }

    /// One frame, drawn whole (ImageIO composites a GIF's partial frames) and scaled down.
    static func frame(_ source: CGImageSource, at index: Int, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    /// The time a frame asks for, from whichever dictionary its type keeps it in.
    static func delay(_ source: CGImageSource, at index: Int) -> Double? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return nil }
        let places: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
        ]
        for (dict, unclamped, clamped) in places {
            guard let d = props[dict] as? [CFString: Any] else { continue }
            if let v = (d[unclamped] as? NSNumber)?.doubleValue, v > 0 { return v }
            if let v = (d[clamped] as? NSNumber)?.doubleValue { return v }
        }
        return nil
    }

    /// Writes an animated PNG (keeps soft edges, unlike a GIF). Atomic: a partial file never
    /// appears under `url`.
    static func writeAnimatedPNG(_ animation: StickerAnimation, to url: URL) -> Bool {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, UTType.png.identifier as CFString,
                                                         animation.frames.count, nil) else { return false }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]] as CFDictionary)
        for (image, delay) in zip(animation.frames, animation.delays) {
            let props = [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay,
                                                         kCGImagePropertyAPNGUnclampedDelayTime: delay]]
            CGImageDestinationAddImage(dest, image, props as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: temp)
            return false
        }
        do {
            try FileManager.default.moveItem(at: temp, to: url)
            return true
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return false
        }
    }
}

/// The user's own stickers: animated PNGs named by id in one folder (the support folder's
/// `stickers`, injected so tests use a temporary one). Files are only ever written, read or
/// removed inside that folder, under names `CustomStickerID` made.
public final class StickerStore: @unchecked Sendable {
    public let directory: URL
    private let fm = FileManager.default
    private let lock = NSLock()

    public init(directory: URL) {
        self.directory = directory
    }

    /// The ids of the user's stickers, oldest first.
    public func ids() -> [String] {
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey],
                                                     options: [.skipsHiddenFiles]) else { return [] }
        let found: [(String, Date)] = urls.compactMap { url in
            guard url.pathExtension == CustomStickerID.fileExtension else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey])
            guard CustomStickerID.isValid(name), values?.isRegularFile == true else { return nil }
            return (name, values?.creationDate ?? .distantPast)
        }
        return found.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }.map(\.0)
    }

    /// Where sticker `id` is kept, or nil if it isn't one of ours.
    public func url(for id: String) -> URL? {
        guard let url = CustomStickerID.file(id, in: directory), fm.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Reads a picture the user chose, scales it to the wing, keeps at most `maxFrames`
    /// frames, and saves it as a new sticker. Returns its id. Slow work: call off the main thread.
    @discardableResult
    public func add(from chosen: URL) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard ids().count < StickerLimits.maxCustom else { throw StickerImportError.full }
        // A link dropped from Finder is the file it points to: its size and kind are that file's.
        let source = chosen.resolvingSymlinksInPath()
        let values = try? source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true else { throw StickerImportError.unreadable }
        // Turned away by its size before a byte of it is read.
        guard (values?.fileSize ?? 0) <= StickerLimits.maxFileBytes else { throw StickerImportError.tooLarge }
        guard let data = try? Data(contentsOf: source, options: .mappedIfSafe) else { throw StickerImportError.unreadable }
        return try save(data)
    }

    /// The same, from the picture's bytes.
    @discardableResult
    public func add(data: Data) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard ids().count < StickerLimits.maxCustom else { throw StickerImportError.full }
        return try save(data)
    }

    private func save(_ data: Data) throws -> String {
        guard data.count <= StickerLimits.maxFileBytes else { throw StickerImportError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw StickerImportError.unreadable }
        // What the bytes are, whatever the file's name says.
        guard let type = CGImageSourceGetType(source).flatMap({ UTType($0 as String) }),
              StickerDecoder.types.contains(where: { type.conforms(to: $0) }) else {
            throw CGImageSourceGetStatus(source) == .statusComplete ? StickerImportError.notAnimation : StickerImportError.unreadable
        }
        guard CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { throw StickerImportError.unreadable }
        guard width * height <= StickerLimits.maxSourcePixels else { throw StickerImportError.tooBigPicture }
        let maxPixel = Self.storedMaxPixel(width: width, height: height)
        guard let animation = StickerDecoder.decode(source, maxPixel: maxPixel, maxFrames: StickerLimits.maxFrames)
        else { throw StickerImportError.unreadable }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw StickerImportError.couldNotSave
        }
        let id = CustomStickerID.make()
        guard let url = CustomStickerID.file(id, in: directory), StickerDecoder.writeAnimatedPNG(animation, to: url)
        else { throw StickerImportError.couldNotSave }
        return id
    }

    /// Removes sticker `id`. Anything that isn't one of ours is left alone.
    public func remove(_ id: String) {
        guard let url = CustomStickerID.file(id, in: directory) else { return }
        try? fm.removeItem(at: url)
    }

    /// The longer side to decode at so a `width` x `height` picture fits the stored box,
    /// never larger than it is.
    static func storedMaxPixel(width: Int, height: Int) -> Int {
        let w = Double(width), h = Double(height)
        let scale = min(1, Double(StickerLimits.storedWidth) / w, Double(StickerLimits.storedHeight) / h)
        return max(1, Int((max(w, h) * scale).rounded()))
    }
}
