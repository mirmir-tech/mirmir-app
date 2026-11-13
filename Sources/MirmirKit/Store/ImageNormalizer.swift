import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

public enum ImageNormalizationError: Error, LocalizedError, Equatable {
    case unreadable
    /// Larger than the server accepts (`MessageLimits.imageBytes`), and it
    /// could not be made smaller.
    case tooLarge(bytes: Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable:
            "The image could not be read. Attach a PNG, JPEG, GIF, WebP or HEIC image."
        case .tooLarge(let bytes):
            "The image is \(Self.megabytes(bytes)) and could not be made smaller; images up to "
                + "\(Self.megabytes(MessageLimits.imageBytes)) can be attached."
        }
    }

    private static func megabytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}

/// Converts an attachment to bytes the server's image decoder accepts. libmir
/// decodes PNG, JPEG, GIF and WebP, but ignores their EXIF orientation:
/// upright ones pass through unchanged, and a tagged one (a phone's rotated
/// or mirrored JPEG) is re-encoded with its pixels turned upright. Anything
/// else ImageIO reads, such as an iPhone's HEIC photo or a TIFF, is
/// re-encoded as JPEG the same way. So is an image larger than the server
/// accepts (`MessageLimits.imageBytes`): it is re-encoded, at lower quality
/// and then fewer pixels until it fits. Vision encoders resize far below
/// those sizes, so the model sees no difference; refusing would only make
/// the user shrink the image by hand. Without ImageIO (Linux) such an image
/// is refused. Decoding a large photo is slow: call it off the main actor.
public enum ImageNormalizer {
    /// The longest side of a converted image; vision encoders resize far
    /// below it, and a 48-megapixel photo would only cost memory.
    static let maxPixelSize = 4096

    /// JPEG encodings tried in order until one fits `MessageLimits.imageBytes`:
    /// the first is the usual conversion, the later ones only shrink an
    /// image that would not fit.
    static let encodings: [(maxPixelSize: Int, quality: Double)] = [
        (maxPixelSize, 0.9), (maxPixelSize, 0.75), (2048, 0.85), (1024, 0.85),
    ]

    public static func normalized(_ data: Data) throws(ImageNormalizationError) -> Data {
        let fits = data.count <= MessageLimits.imageBytes
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw .unreadable }
        if fits, isServerFormat(data), isUpright(source) { return data }
        for encoding in encodings {
            let jpeg = try self.jpeg(source, maxPixelSize: encoding.maxPixelSize, quality: encoding.quality)
            if jpeg.count <= MessageLimits.imageBytes { return jpeg }
        }
        throw .tooLarge(bytes: data.count)
        #else
        guard isServerFormat(data) else { throw .unreadable }
        guard fits else { throw .tooLarge(bytes: data.count) }
        return data
        #endif
    }

    #if canImport(ImageIO)
    /// The image upright as JPEG, its longest side at most `maxPixelSize`.
    private static func jpeg(
        _ source: CGImageSource, maxPixelSize: Int, quality: Double
    ) throws(ImageNormalizationError) -> Data {
        // A thumbnail at full size applies the photo's EXIF orientation to
        // the pixels: the server's decoder ignores the orientation tag.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw .unreadable }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            throw .unreadable
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, try opaque(image), properties)
        guard CGImageDestinationFinalize(destination) else { throw .unreadable }
        return output as Data
    }

    /// Whether the stored pixels are already the way the image is shown: no
    /// EXIF orientation, or the identity one.
    static func isUpright(_ source: CGImageSource) -> Bool {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        return orientation == CGImagePropertyOrientation.up.rawValue
    }

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
