import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

public enum ImageNormalizationError: Error, LocalizedError, Equatable {
    case unreadable

    public var errorDescription: String? {
        "The image could not be read. Attach a PNG, JPEG, GIF, WebP or HEIC image."
    }
}

/// Converts an attachment to bytes the server's image decoder accepts. libmir
/// decodes PNG, JPEG, GIF and WebP; those pass through unchanged. Anything
/// else ImageIO reads, such as an iPhone's HEIC photo or a TIFF, is
/// re-encoded as JPEG. Decoding a large photo is slow: call it off the main
/// actor.
public enum ImageNormalizer {
    /// The longest side of a converted image; vision encoders resize far
    /// below it, and a 48-megapixel photo would only cost memory.
    static let maxPixelSize = 4096

    public static func normalized(_ data: Data) throws(ImageNormalizationError) -> Data {
        if isServerFormat(data) { return data }
        #if canImport(ImageIO)
        // A thumbnail at full size applies the photo's EXIF orientation to
        // the pixels: the server's decoder ignores the orientation tag.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw .unreadable }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            throw .unreadable
        }
        CGImageDestinationAddImage(destination, try opaque(image), [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw .unreadable }
        return output as Data
        #else
        throw .unreadable
        #endif
    }

    #if canImport(ImageIO)
    /// JPEG has no alpha: transparent pixels would turn black, so the image
    /// is laid on white, as Preview shows it.
    private static func opaque(_ image: CGImage) throws(ImageNormalizationError) -> CGImage {
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst else { return image }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw .unreadable }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let flattened = context.makeImage() else { throw .unreadable }
        return flattened
    }
    #endif

    /// PNG, JPEG, GIF or WebP, by signature.
    static func isServerFormat(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        func starts(_ prefix: [UInt8]) -> Bool { bytes.starts(with: prefix) }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return true }
        if starts([0xFF, 0xD8, 0xFF]) { return true }
        if starts(Array("GIF87a".utf8)) || starts(Array("GIF89a".utf8)) { return true }
        return bytes.count == 12 && starts(Array("RIFF".utf8)) && Array(bytes[8..<12]) == Array("WEBP".utf8)
    }
}
