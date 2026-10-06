import CoreGraphics
import Foundation
import ImageIO
import CasementCore
import Testing
import UniformTypeIdentifiers
@testable import CasementSystem

/// The user's stickers, in a temporary folder: importing, the caps, files that aren't
/// stickers, and removing.
@Suite struct StickerStoreTests {
    /// A fresh folder for one test, and the store on it.
    private func store() -> (StickerStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("casement-stickers-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (StickerStore(directory: root.appendingPathComponent("stickers")), root)
    }

    /// An animated picture of `frames` frames, each a different shade, `width` x `height`.
    static func animation(type: UTType = .gif, frames: Int, width: Int = 40, height: Int = 40,
                          delay: Double? = 0.05) -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, frames, nil)!
        if type == .gif {
            CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        for i in 0..<frames {
            let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: CGFloat(i % 10) / 10, green: 0.5, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 4, y: 4, width: width - 8, height: height - 8))
            var props: [CFString: Any] = [:]
            if let delay {
                props = type == .gif
                    ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]]
                    : [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]]
            }
            CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(dest))
        return data as Data
    }

    private func write(_ data: Data, _ name: String, in dir: URL) -> URL {
        let url = dir.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }

    @Test func aGIFBecomesASticker() throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = write(Self.animation(frames: 12, width: 300, height: 200), "dance.gif", in: root)
        let id = try store.add(from: source)
        #expect(CustomStickerID.isValid(id))
        #expect(store.ids() == [id])
        let url = try #require(store.url(for: id))
        #expect(url.deletingLastPathComponent().path == store.directory.path)
        // Scaled to the wing's box, every frame kept with its time.
        let a = try #require(StickerDecoder.decode(url: url, maxPixel: 1000))
        #expect(a.frames.count == 12)
        #expect(a.frames.allSatisfy { $0.width <= StickerLimits.storedWidth && $0.height <= StickerLimits.storedHeight })
        #expect(a.frames[0].height == 80)
        #expect(abs(a.aspect - 1.5) < 0.05)
        #expect(a.delays.allSatisfy { abs($0 - 0.05) < 0.005 })
        // The file it came from is left as it was.
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func animatedPNGsWork() throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try store.add(data: Self.animation(type: .png, frames: 5))
        let a = try #require(StickerDecoder.decode(url: store.url(for: id)!, maxPixel: 64))
        #expect(a.frames.count == 5 && a.isAnimated)
    }

    @Test func longAnimationsAreThinnedNotCut() throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try store.add(data: Self.animation(frames: 400, width: 16, height: 16, delay: 0.03))
        let a = try #require(StickerDecoder.decode(url: store.url(for: id)!, maxPixel: 32))
        #expect(a.frames.count == StickerLimits.maxFrames)
        #expect(abs(a.duration - 12) < 0.2, "the loop lasts as long as it did")
    }

    @Test func zeroDelaysPlayAtASafePace() throws {
        let a = try #require(StickerDecoder.decode(data: Self.animation(frames: 6, delay: 0), maxPixel: 32))
        #expect(a.delays.allSatisfy { $0 >= StickerLimits.minDelay })
        let none = try #require(StickerDecoder.decode(data: Self.animation(frames: 3, delay: nil), maxPixel: 32))
        #expect(none.delays.allSatisfy { $0 >= StickerLimits.minDelay && $0 <= StickerLimits.maxDelay })
    }

    /// A GIF saved with 10 ms frames plays at a browser's 100 ms, in the island and in the
    /// copy that is kept; one with 20 ms frames keeps them.
    @Test func tenMillisecondGIFsKeepTheirBrowserPace() throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let fast = try store.add(data: Self.animation(frames: 4, delay: 0.01))
        let kept = try #require(StickerDecoder.decode(url: store.url(for: fast)!, maxPixel: 32))
        #expect(kept.delays.allSatisfy { abs($0 - 0.1) < 0.005 }, "\(kept.delays)")
        let brisk = try #require(StickerDecoder.decode(data: Self.animation(frames: 4, delay: 0.02), maxPixel: 32))
        #expect(brisk.delays.allSatisfy { abs($0 - 0.02) < 0.005 }, "\(brisk.delays)")
    }

    @Test func filesThatArentStickersAreTurnedAway() throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        // Text dressed up as a GIF.
        let fake = write(Data("GIF89a, honestly".utf8), "fake.gif", in: root)
        #expect(throws: StickerImportError.self) { try store.add(from: fake) }
        // A JPEG: a picture, but not one a sticker can be.
        let jpeg = NSMutableData()
        let dest = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil)!
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        #expect(throws: StickerImportError.notAnimation) { try store.add(data: jpeg as Data) }
        // A GIF cut off half way.
        let whole = Self.animation(frames: 8)
        #expect(throws: StickerImportError.self) { try store.add(data: whole.prefix(whole.count / 3)) }
        // A folder, and nothing at all.
        #expect(throws: StickerImportError.unreadable) { try store.add(from: root) }
        #expect(throws: StickerImportError.unreadable) { try store.add(from: root.appendingPathComponent("missing.gif")) }
        #expect(throws: StickerImportError.self) { try store.add(data: Data()) }
        #expect(store.ids().isEmpty, "nothing half-written is left behind")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    /// A symbolic link is the file it points to: a GIF behind one is added, and a big file
    /// behind one is still turned away by its own size.
    @Test func linksAreFollowedToTheirFile() throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let gif = write(Self.animation(frames: 3), "dance.gif", in: root)
        let link = root.appendingPathComponent("link.gif")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: gif)
        let id = try store.add(from: link)
        #expect(store.ids() == [id])
        var big = Self.animation(frames: 2)
        big.append(Data(count: StickerLimits.maxFileBytes))
        let huge = write(big, "huge.gif", in: root)
        let bigLink = root.appendingPathComponent("big-link.gif")
        try FileManager.default.createSymbolicLink(at: bigLink, withDestinationURL: huge)
        #expect(throws: StickerImportError.tooLarge) { try store.add(from: bigLink) }
    }

    @Test func bigFilesAreTurnedAwayUnread() throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        var big = Self.animation(frames: 2)
        big.append(Data(count: StickerLimits.maxFileBytes))
        let url = write(big, "huge.gif", in: root)
        #expect(throws: StickerImportError.tooLarge) { try store.add(from: url) }
        #expect(throws: StickerImportError.tooLarge) { try store.add(data: big) }
    }

    @Test func enormousPicturesAreTurnedAway() throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        // A GIF whose header claims 65535 x 65535 pixels, with almost nothing after it.
        var gif = Data("GIF89a".utf8)
        gif += [0xFF, 0xFF, 0xFF, 0xFF, 0x80, 0x00, 0x00]  // screen size, a 2-colour table
        gif += [0, 0, 0, 255, 255, 255]
        gif += [0x2C, 0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]  // one image, as big
        gif += [0x02, 0x02, 0x44, 0x01, 0x00, 0x3B]
        #expect(throws: StickerImportError.self) { try store.add(data: gif) }
        #expect(store.ids().isEmpty)
    }

    @Test func twelveIsTheMost() throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let small = Self.animation(frames: 2, width: 8, height: 8)
        for _ in 0..<StickerLimits.maxCustom { try store.add(data: small) }
        #expect(store.ids().count == StickerLimits.maxCustom)
        #expect(throws: StickerImportError.full) { try store.add(data: small) }
        #expect(store.ids().count == StickerLimits.maxCustom)
    }

    @Test func removingTouchesOnlyStickers() throws {
        let (store, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try store.add(data: Self.animation(frames: 2))
        // Things beside and above the folder that a hostile id might try to reach.
        let outside = write(Data("keep".utf8), "keep.png", in: root)
        let beside = write(Data("keep".utf8), "notes.txt", in: store.directory)
        for hostile in ["../keep", "../../keep", "notes", "", "/etc/hosts", id + "/.."] {
            store.remove(hostile)
        }
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(FileManager.default.fileExists(atPath: beside.path))
        #expect(store.ids() == [id], "files that aren't stickers aren't listed")
        store.remove(id)
        #expect(store.ids().isEmpty)
        #expect(store.url(for: id) == nil)
    }

    @Test func theBuiltInsAreSmallSmoothLoops() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Stickers").standardizedFileURL
        for b in BuiltInSticker.allCases {
            let url = folder.appendingPathComponent(b.fileName)
            let size = try #require(try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, "\(b.fileName) is missing")
            #expect(size < 60 * 1024, "\(b.fileName) is \(size / 1024) KB")
            let a = try #require(StickerDecoder.decode(url: url, maxPixel: 64))
            #expect((12...24).contains(a.frames.count), "\(b.fileName): \(a.frames.count) frames")
            #expect(a.frames[0].width == 64 && a.frames[0].height == 64, "2x for 32 points")
            // 40 to 60 ms a frame; a pose held still is one frame that waits longer.
            #expect(a.delays.allSatisfy { $0 >= 0.039 && $0 <= 0.5 }, "\(b.fileName): \(a.delays)")
            #expect((0.8...2).contains(a.duration), "\(b.fileName) loops every \(a.duration) s")
            // Transparent around the edge, so only the sticker shows on the island.
            #expect(Self.alphaAtCorner(a.frames[0]) == 0, "\(b.fileName)")
        }
    }

    private static func alphaAtCorner(_ image: CGImage) -> UInt8 {
        var pixel = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixel[3]
    }
}
