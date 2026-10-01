import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Validates and prepares a dropped/imported image file for `MockupAsset` storage. Pure,
/// `nonisolated`, ImageIO-only — no SwiftData — so it is unit-testable without a `ModelContext`.
/// Deliberately does not reuse `ImageBase64Engine` (a sibling feature); features never import
/// each other, per CLAUDE.md.
public nonisolated enum MockupAssetImportError: Error, LocalizedError, Equatable {
    case unreadable
    case unsupportedImage
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .unreadable: "Couldn't read that file."
        case .unsupportedImage: "That file isn't a supported image format."
        case .tooLarge: "That image is too large to import."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unreadable: "Check the file still exists and try again."
        case .unsupportedImage: "Use PNG, JPEG, HEIC, TIFF, or GIF."
        case .tooLarge: "Resize the image and try again."
        }
    }
}

public nonisolated enum MockupAssetImport {
    /// Longest side, in pixels, an asset is allowed to keep. Anything bigger is downscaled and
    /// re-encoded so a multi-thousand-pixel photo can't blow up the mockup's device layout or
    /// balloon the SwiftData store.
    public static let maxPixelSize = 2048

    public nonisolated struct Prepared: Equatable {
        public var name: String
        public var data: Data
        public var pixelWidth: Int
        public var pixelHeight: Int
    }

    /// Strips characters that would break out of a Swift string literal (the name is spliced
    /// into source as `Image("name")`) or otherwise make an awkward file/tab title, trims
    /// whitespace, and falls back to a default when nothing usable remains.
    public static func sanitize(_ name: String) -> String {
        let disallowed = CharacterSet(charactersIn: "\"\\").union(.newlines).union(.controlCharacters)
        let cleaned = name.unicodeScalars
            .filter { !disallowed.contains($0) }
            .map(Character.init)
        let collapsed = String(String(cleaned)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " "))
        let trimmed = collapsed.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "image" : trimmed
    }

    /// Validates `data` decodes as an image, reads its pixel dimensions, and downscales it when
    /// either side exceeds `maxPixelSize`. Small images pass through with their original bytes
    /// (preserving PNG/JPEG/HEIC); oversized ones are re-encoded as PNG from a CoreGraphics
    /// thumbnail.
    public static func prepare(data: Data, filename: String) throws -> Prepared {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { throw MockupAssetImportError.unreadable }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { throw MockupAssetImportError.unsupportedImage }

        let name = sanitize((filename as NSString).deletingPathExtension)
        let longestSide = max(width, height)

        guard longestSide > maxPixelSize else {
            return Prepared(name: name, data: data, pixelWidth: width, pixelHeight: height)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        else { throw MockupAssetImportError.tooLarge }

        let resized = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(resized, UTType.png.identifier as CFString, 1, nil)
        else { throw MockupAssetImportError.tooLarge }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { throw MockupAssetImportError.tooLarge }

        return Prepared(
            name: name,
            data: resized as Data,
            pixelWidth: thumbnail.width,
            pixelHeight: thumbnail.height
        )
    }
}
