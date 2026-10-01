import AppKit
import Foundation
import Testing
@testable import SwiftyUI

/// `MockupAssetImport` is pure ImageIO — no `ModelContext` — so these run without SwiftData.
@Suite
struct MockupAssetImportTests {

    // MARK: - sanitize

    @Test func sanitizeStripsQuotesAndControlCharacters() {
        let input = "Weird\"Name\n\t"
        #expect(MockupAssetImport.sanitize(input) == "WeirdName")
    }

    @Test func sanitizeFallsBackToDefaultWhenNothingUsableRemains() {
        #expect(MockupAssetImport.sanitize("") == "image")
        #expect(MockupAssetImport.sanitize("   ") == "image")
        #expect(MockupAssetImport.sanitize("\"\"") == "image")
    }

    @Test func sanitizeCollapsesWhitespaceRunsAndTrims() {
        #expect(MockupAssetImport.sanitize("  Logo   Mark  ") == "Logo Mark")
    }

    // MARK: - prepare

    @Test func prepareKeepsSmallImagesByteIdenticalAndReadsDimensions() throws {
        let data = Self.makePNGData(width: 64, height: 32)
        let prepared = try MockupAssetImport.prepare(data: data, filename: "Logo.png")
        #expect(prepared.name == "Logo")
        #expect(prepared.pixelWidth == 64)
        #expect(prepared.pixelHeight == 32)
        #expect(prepared.data == data)
    }

    @Test func prepareSanitizesTheFilenameStem() throws {
        let data = Self.makePNGData(width: 8, height: 8)
        let prepared = try MockupAssetImport.prepare(data: data, filename: "My \"Logo\".png")
        #expect(prepared.name == "My Logo")
    }

    @Test func prepareDownscalesImagesOverTheMaxPixelSize() throws {
        let data = Self.makePNGData(width: 2200, height: 1100)
        let prepared = try MockupAssetImport.prepare(data: data, filename: "hero.png")
        #expect(prepared.pixelWidth <= MockupAssetImport.maxPixelSize)
        #expect(prepared.pixelHeight <= MockupAssetImport.maxPixelSize)
        #expect(max(prepared.pixelWidth, prepared.pixelHeight) == MockupAssetImport.maxPixelSize)
        // Aspect ratio survives the downscale (2:1 in, 2:1 out).
        #expect(prepared.pixelWidth == prepared.pixelHeight * 2)
        #expect(prepared.data != data)
    }

    @Test func prepareThrowsOnEmptyData() {
        #expect(throws: MockupAssetImportError.self) {
            try MockupAssetImport.prepare(data: Data(), filename: "empty.png")
        }
    }

    @Test func prepareThrowsOnUnreadableData() {
        #expect(throws: MockupAssetImportError.self) {
            try MockupAssetImport.prepare(data: Data("not an image".utf8), filename: "junk.png")
        }
    }

    // MARK: - Fixtures

    /// A solid-fill PNG at an exact pixel size, independent of the current screen's backing
    /// scale factor (an `NSImage(size:)` + `lockFocus()` render would otherwise pick up a
    /// Retina screen's 2x factor and produce double the requested pixels).
    private static func makePNGData(width: Int, height: Int) -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { fatalError("Could not create test bitmap") }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Could not encode test PNG")
        }
        return png
    }
}
