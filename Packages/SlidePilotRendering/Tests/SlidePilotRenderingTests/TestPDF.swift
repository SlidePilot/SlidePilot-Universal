import CoreGraphics
import Foundation
import PDFKit
import Testing

/// Builds small PDFs in memory, so the tests need no files on disk.
enum TestPDF {
    /// 4:3 Beamer page size in points.
    static let pageSize = CGSize(width: 362.8, height: 272.1)

    /// Every page has its left half red and its right half blue (unrotated), so tests can
    /// check which part of a page was rendered.
    static func make(
        pages: Int,
        size: CGSize = pageSize,
        userPassword: String? = nil,
        ownerPassword: String? = nil
    ) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: size)
        var info: [CFString: Any] = [:]
        if let userPassword {
            info[kCGPDFContextUserPassword] = userPassword
            info[kCGPDFContextOwnerPassword] = ownerPassword ?? userPassword
        } else if let ownerPassword {
            info[kCGPDFContextOwnerPassword] = ownerPassword
            info[kCGPDFContextAllowsCopying] = false
        }
        guard
            let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)
        else { return Data() }
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// Sets `/Rotate` of each page, like a PDF that was saved rotated.
    static func rotating(_ data: Data, by rotations: [Int]) throws -> Data {
        let document = try #require(PDFDocument(data: data))
        for (index, rotation) in rotations.enumerated() {
            document.page(at: index)?.rotation = rotation
        }
        return try #require(document.dataRepresentation())
    }
}

/// Reads pixels of rendered images.
enum PixelProbe {
    enum Color: Equatable {
        case red, blue, white, other
    }

    /// The color at a point given as a fraction of the image, origin top left.
    static func color(of image: CGImage, atUnit point: CGPoint) -> Color {
        var pixel: [UInt8] = [0, 0, 0, 0]
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            let x = point.x * CGFloat(image.width)
            let y = (1 - point.y) * CGFloat(image.height)
            context.draw(image, in: CGRect(x: -x, y: -y, width: CGFloat(image.width), height: CGFloat(image.height)))
            return true
        }
        guard drawn else { return .other }
        let (r, g, b) = (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
        switch (r, g, b) {
        case (200..., ..<60, ..<60): return .red
        case (..<60, ..<60, 200...): return .blue
        case (220..., 220..., 220...): return .white
        default: return .other
        }
    }
}
