// PROTOTYPE (issue #8): render time and memory measurements for sizing the render cache.
// Not production code; kept out of main. Results are printed with the prefix "RENDERMEASURE".
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing

#if canImport(Darwin)
import Darwin
#endif

private struct Target: Sendable {
    let name: String
    let width: Int
    let height: Int
}

private let targets: [Target] = [
    Target(name: "thumbnail 200x150pt @2x", width: 400, height: 300),
    Target(name: "presenter next 600x450pt @2x", width: 1200, height: 900),
    Target(name: "presenter current 900x675pt @2x", width: 1800, height: 1350),
    Target(name: "full screen 1920x1080", width: 1920, height: 1080),
    Target(name: "full screen 2560x1440", width: 2560, height: 1440),
    Target(name: "iPad Pro 13 2752x2064", width: 2752, height: 2064),
    Target(name: "full screen 3840x2160 (4K)", width: 3840, height: 2160),
    Target(name: "full screen 5120x2880 (5K)", width: 5120, height: 2880),
    Target(name: "full screen 6016x3384 (6K)", width: 6016, height: 3384),
]

private func fixtureURL(_ name: String) -> URL {
    // Tests/SlidePilotRenderingTests/<file> → repo root is five levels up.
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures").appendingPathComponent(name)
}

private struct VM {
    var footprint = 0, internalBytes = 0, compressed = 0, resident = 0
    static func - (a: VM, b: VM) -> VM {
        VM(footprint: a.footprint - b.footprint, internalBytes: a.internalBytes - b.internalBytes,
           compressed: a.compressed - b.compressed, resident: a.resident - b.resident)
    }
}

private func vm() -> VM {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return VM() }
    return VM(footprint: Int(info.phys_footprint), internalBytes: Int(info.internal),
              compressed: Int(info.compressed), resident: Int(info.resident_size))
}

private func footprint() -> Int { vm().footprint }

/// Renders a page aspect-fit into the target size, the way a cache would store it.
private func render(_ page: PDFPage, into target: Target) -> CGImage {
    let box = page.bounds(for: .mediaBox)
    let scale = min(Double(target.width) / box.width, Double(target.height) / box.height)
    let width = Int((box.width * scale).rounded())
    let height = Int((box.height * scale).rounded())
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -box.minX, y: -box.minY)
    page.draw(with: .mediaBox, to: context)
    return context.makeImage()!
}

private func ms(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

private func stats(_ values: [Double]) -> String {
    let sorted = values.sorted()
    let median = sorted[sorted.count / 2]
    let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    return String(format: "median %.1f ms | p95 %.1f ms | max %.1f ms", median, p95, sorted.last!)
}

private func log(_ line: String) {
    print("RENDERMEASURE \(line)")
}

#if os(macOS)
private let platform = "macOS"
#else
private let platform = "iOS"
#endif


private func mib(_ bytes: Int) -> String { String(format: "%.1f MiB", Double(bytes) / 1_048_576) }

/// Writes a synthetic "heavy" Beamer-sized deck: every page has a JPEG photo (2400x1800,
/// DCT-encoded like a photo in a real deck) and 2000 stroked Bézier curves. The repo fixtures
/// are text-only and render in a few ms, so this gives an upper bound for image-heavy slides.
private func makeHeavyDeck(pages: Int) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("heavy-deck-\(UUID().uuidString).pdf")
    var box = CGRect(x: 0, y: 0, width: 362.8, height: 272.1)
    let pdf = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
    let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    var seed: UInt64 = 42
    func next() -> UInt64 {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return seed >> 33
    }
    for pageIndex in 0..<pages {
        let width = 2400, height = 1800
        let bitmap = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        // Photo-like content: gradients plus many soft shapes (compresses like a photo, not like noise).
        for _ in 0..<400 {
            let r = Double(next() % 256) / 255, g = Double(next() % 256) / 255, b = Double(next() % 256) / 255
            bitmap.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 0.35))
            let size = Double(next() % 600 + 40)
            bitmap.fillEllipse(in: CGRect(x: Double(next() % UInt64(width)), y: Double(next() % UInt64(height)), width: size, height: size * 0.7))
        }
        let raw = try #require(bitmap.makeImage())
        let jpegData = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(jpegData, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, raw, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let provider = try #require(CGDataProvider(data: jpegData))
        let photo = try #require(CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))

        pdf.beginPDFPage(nil)
        pdf.draw(photo, in: CGRect(x: 10, y: 40, width: 200, height: 150))
        pdf.setLineWidth(0.3)
        for _ in 0..<2000 {
            pdf.setStrokeColor(CGColor(red: Double(next() % 256) / 255, green: 0.3, blue: Double(pageIndex) / Double(pages), alpha: 1))
            pdf.move(to: CGPoint(x: 210 + Double(next() % 150), y: Double(next() % 270)))
            pdf.addCurve(
                to: CGPoint(x: 210 + Double(next() % 150), y: Double(next() % 270)),
                control1: CGPoint(x: 210 + Double(next() % 150), y: Double(next() % 270)),
                control2: CGPoint(x: 210 + Double(next() % 150), y: Double(next() % 270)))
            pdf.strokePath()
        }
        pdf.endPDFPage()
    }
    pdf.closePDF()
    return url
}

@Suite(.serialized) struct RenderMeasurements {
    @Test func openLargeDeck() throws {
        let clock = ContinuousClock()
        var document: PDFDocument?
        let elapsed = clock.measure { document = PDFDocument(url: fixtureURL("large-deck.pdf")) }
        let doc = try #require(document)
        log("[\(platform)] open large-deck.pdf (\(doc.pageCount) pages): \(String(format: "%.1f", ms(elapsed))) ms")
    }

    private func measureRenderTimes(_ doc: PDFDocument, label: String, maxPages: Int) throws {
        let pageCount = min(doc.pageCount, maxPages)
        let clock = ContinuousClock()
        for target in targets {
            var cold: [Double] = []
            var warm: [Double] = []
            var bytes = 0
            var size = ""
            // Two passes: PDFKit keeps parsed page content after the first.
            for pass in 0..<2 {
                for index in 0..<pageCount {
                    let page = try #require(doc.page(at: index))
                    try autoreleasepool {
                        var image: CGImage?
                        let elapsed = clock.measure { image = render(page, into: target) }
                        if pass == 0 { cold.append(ms(elapsed)) } else { warm.append(ms(elapsed)) }
                        let rendered = try #require(image)
                        bytes = rendered.bytesPerRow * rendered.height
                        size = "\(rendered.width)x\(rendered.height)"
                    }
                }
            }
            log("[\(platform)] \(label) | \(target.name) | image \(size) | \(mib(bytes)) | cold \(stats(cold)) | warm \(stats(warm))")
        }
    }

    @Test func renderTimePerTarget() throws {
        for file in ["large-deck.pdf", "plain-slides.pdf", "notes-right.pdf"] {
            let doc = try #require(PDFDocument(url: fixtureURL(file)))
            try measureRenderTimes(doc, label: file, maxPages: 40)
        }
    }

    @Test func renderTimeHeavyPages() throws {
        let clock = ContinuousClock()
        var url: URL?
        let made = try clock.measure { url = try makeHeavyDeck(pages: 8) }
        let deck = try #require(url)
        defer { try? FileManager.default.removeItem(at: deck) }
        let size = (try? FileManager.default.attributesOfItem(atPath: deck.path)[.size] as? Int) ?? 0
        log("[\(platform)] heavy deck: 8 pages, \(mib(size)) on disk, generated in \(String(format: "%.0f", ms(made))) ms")
        let doc = try #require(PDFDocument(url: deck))
        try measureRenderTimes(doc, label: "heavy (synthetic)", maxPages: 8)
    }

    @Test func retainedMemoryPerImage() throws {
        let heavyURL = try makeHeavyDeck(pages: 8)
        defer { try? FileManager.default.removeItem(at: heavyURL) }
        #if os(iOS)
        log("[\(platform)] os_proc_available_memory before: \(mib(os_proc_available_memory()))")
        #endif
        for (label, url) in [("large-deck", fixtureURL("large-deck.pdf")), ("heavy", heavyURL)] {
            let doc = try #require(PDFDocument(url: url))
            for target in targets where target.width >= 1200 {
                let count = 30
                var images: [CGImage] = []
                var computed = 0
                var checksum = 0
                let before = vm()
                for index in 0..<count {
                    try autoreleasepool {
                        let image = render(try #require(doc.page(at: index % doc.pageCount)), into: target)
                        computed += image.bytesPerRow * image.height
                        images.append(image)
                    }
                }
                let mid = vm()
                // Touch every image's pixels, as drawing it on screen would.
                for image in images {
                    if let data = image.dataProvider?.data { checksum &+= CFDataGetLength(data) }
                }
                let after = vm()
                #if os(iOS)
                log("[\(platform)] os_proc_available_memory with \(count) retained images (\(target.name), \(label)): \(mib(os_proc_available_memory()))")
                #endif
                let d1 = mid - before, d2 = after - before
                log("[\(platform)] retained \(count) images, \(label) | \(target.name) | computed \(mib(computed)) | after render: footprint \(mib(d1.footprint)) internal \(mib(d1.internalBytes)) compressed \(mib(d1.compressed)) resident \(mib(d1.resident)) | after reading pixels: footprint \(mib(d2.footprint)) resident \(mib(d2.resident)) (\(checksum))")
                images.removeAll()
            }
        }
    }

    @Test func retainedOwnBuffers() throws {
        // Same as above, but the pixels live in buffers the test owns (CGContext with our own data),
        // so the footprint must grow by the computed size. Checks the counter itself.
        let doc = try #require(PDFDocument(url: fixtureURL("large-deck.pdf")))
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        for target in targets where target.width == 3840 || target.width == 2752 {
            var buffers: [UnsafeMutableRawPointer] = []
            var computed = 0
            let before = vm()
            for index in 0..<20 {
                try autoreleasepool {
                    let page = try #require(doc.page(at: index))
                    let box = page.bounds(for: .mediaBox)
                    let scale = min(Double(target.width) / box.width, Double(target.height) / box.height)
                    let width = Int((box.width * scale).rounded()), height = Int((box.height * scale).rounded())
                    let bytes = width * 4 * height
                    let buffer = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 64)
                    let context = try #require(CGContext(
                        data: buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
                    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                    context.scaleBy(x: scale, y: scale)
                    page.draw(with: .mediaBox, to: context)
                    buffers.append(buffer)
                    computed += bytes
                }
            }
            let delta = vm() - before
            log("[\(platform)] retained 20 own buffers | \(target.name) | computed \(mib(computed)) | footprint \(mib(delta.footprint)) resident \(mib(delta.resident))")
            buffers.forEach { $0.deallocate() }
        }
        #if os(iOS)
        log("[\(platform)] os_proc_available_memory \(mib(os_proc_available_memory()))")
        #endif
    }

    @Test func discardedImagesWithoutAutoreleasePool() throws {
        // Renders 60 4K pages and drops each image right away. Without a pool the footprint grows,
        // because PDFKit's drawing autoreleases objects that hold on to the bitmap.
        let doc = try #require(PDFDocument(url: fixtureURL("large-deck.pdf")))
        let target = targets.first { $0.width == 3840 }!
        let start = footprint()
        for index in 0..<60 { _ = render(try #require(doc.page(at: index)), into: target) }
        let withoutPool = footprint()
        for index in 60..<120 {
            try autoreleasepool { _ = render(try #require(doc.page(at: index)), into: target) }
        }
        let withPool = footprint()
        log("[\(platform)] 60 discarded 4K renders | without autoreleasepool +\(mib(withoutPool - start)) | then with autoreleasepool +\(mib(withPool - withoutPool))")
    }

    @Test func neighborhoodFill() async throws {
        // Time to render 20 pages at 4K, sequentially and with 4 tasks that each open their own
        // PDFDocument (no PDFPage shared across threads, DEF-02).
        for (label, url) in [("large-deck", fixtureURL("large-deck.pdf")), ("heavy", try makeHeavyDeck(pages: 20))] {
            let target = targets.first { $0.width == 3840 }!
            let clock = ContinuousClock()
            let pages = label == "heavy" ? Array(0..<20) : Array(100..<120)
            let sequential = try clock.measure {
                let doc = try #require(PDFDocument(url: url))
                for index in pages {
                    try autoreleasepool { _ = render(try #require(doc.page(at: index)), into: target) }
                }
            }
            let parallel = try await clock.measure {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for worker in 0..<4 {
                        group.addTask {
                            let doc = try #require(PDFDocument(url: url))
                            for index in pages where index % 4 == worker {
                                try autoreleasepool { _ = render(try #require(doc.page(at: index)), into: target) }
                            }
                        }
                    }
                    try await group.waitForAll()
                }
            }
            log("[\(platform)] neighborhood 20 pages @4K, \(label) | sequential \(String(format: "%.0f", ms(sequential))) ms | 4 tasks \(String(format: "%.0f", ms(parallel))) ms (incl. opening the document per task)")
            if label == "heavy" { try? FileManager.default.removeItem(at: url) }
        }
    }
}
