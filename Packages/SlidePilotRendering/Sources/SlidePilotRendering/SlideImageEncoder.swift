import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Compresses rendered slides for the remote (REM-04). Slides are opaque, so JPEG keeps
/// them small without visible loss at this quality.
public enum SlideImageEncoder {
    public enum EncodingError: Error, Sendable {
        case failed
    }

    /// JPEG data of `image`. `quality` is 0…1.
    public static func jpeg(_ image: CGImage, quality: Double = 0.8) throws(EncodingError) -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw .failed
        }
        let options = [kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1)] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { throw .failed }
        return data as Data
    }
}
