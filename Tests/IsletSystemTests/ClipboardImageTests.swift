import AppKit
import Foundation
import Testing
@testable import IsletSystem

/// A copied picture's size comes from its header, without drawing it; anything else isn't one.
@Suite struct ClipboardImageTests {
    @Test func pictureSizeIsReadFromTheHeader() throws {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 25, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let size = try #require(ClipboardMonitor.pixelSize(png))
        #expect(size.width == 40 && size.height == 25)
        let tiff = try #require(rep.representation(using: .tiff, properties: [:]))
        #expect(ClipboardMonitor.pixelSize(tiff)?.height == 25)
        #expect(ClipboardMonitor.pixelSize(Data("not a picture".utf8)) == nil)
        #expect(ClipboardMonitor.pixelSize(Data()) == nil)
    }
}
