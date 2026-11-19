import Foundation
import Testing
import UniformTypeIdentifiers
@testable import SlidePilotCore

@Suite struct LinkedFileTests {
    let pdf = URL(filePath: "/talks/2026/media.pdf")

    @Test func resolvesPathRelativeToThePDF() {
        #expect(LinkedFile.resolve("media/test-pattern.mp4", relativeTo: pdf) == URL(filePath: "/talks/2026/media/test-pattern.mp4"))
        #expect(LinkedFile.resolve("plain-slides.pdf", relativeTo: pdf) == URL(filePath: "/talks/2026/plain-slides.pdf"))
    }

    @Test func resolvesParentFolderAndDotSegments() {
        #expect(LinkedFile.resolve("../videos/a.mov", relativeTo: pdf) == URL(filePath: "/talks/videos/a.mov"))
        #expect(LinkedFile.resolve("./a.mov", relativeTo: pdf) == URL(filePath: "/talks/2026/a.mov"))
    }

    /// The old app used `URL(string:relativeTo:)`, which fails on spaces.
    @Test func resolvesPathsWithSpaces() {
        #expect(LinkedFile.resolve("my video.mp4", relativeTo: pdf) == URL(filePath: "/talks/2026/my video.mp4"))
    }

    @Test func keepsAbsolutePathsAndFileURLs() {
        #expect(LinkedFile.resolve("/Movies/a.mp4", relativeTo: pdf) == URL(filePath: "/Movies/a.mp4"))
        #expect(LinkedFile.resolve("file:///Movies/a.mp4", relativeTo: pdf) == URL(filePath: "/Movies/a.mp4"))
    }

    @Test func keepsWebAddresses() {
        #expect(LinkedFile.resolve("https://example.com/a.mp4", relativeTo: pdf) == URL(string: "https://example.com/a.mp4"))
        #expect(LinkedFile.resolve("http://example.com/a.mp4", relativeTo: pdf) == URL(string: "http://example.com/a.mp4"))
    }

    @Test func refusesOtherSchemesAndEmptyReferences() {
        #expect(LinkedFile.resolve("javascript:alert(1)", relativeTo: pdf) == nil)
        #expect(LinkedFile.resolve("ftp://example.com/a.mp4", relativeTo: pdf) == nil)
        #expect(LinkedFile.resolve("  ", relativeTo: pdf) == nil)
    }
}

@Suite struct RunLinkPolicyTests {
    @Test(arguments: ["pdf", "mp4", "mov", "key", "pptx", "docx", "txt", "png", "html"])
    func opensDocumentsAndMedia(_ fileExtension: String) {
        #expect(RunLinkPolicy.allowsOpening(UTType(filenameExtension: fileExtension), fileExtension: fileExtension))
    }

    @Test(arguments: ["app", "command", "sh", "scpt", "pkg", "workflow", "exe", "py", "fileloc", "webloc"])
    func refusesProgramsAndScripts(_ fileExtension: String) {
        #expect(!RunLinkPolicy.allowsOpening(UTType(filenameExtension: fileExtension), fileExtension: fileExtension))
    }

    @Test func refusesExecutablesAndUnknownTypes() {
        #expect(!RunLinkPolicy.allowsOpening(.unixExecutable))
        #expect(!RunLinkPolicy.allowsOpening(nil))
        // A runnable format without a registered type is refused by its extension.
        #expect(!RunLinkPolicy.allowsOpening(.data, fileExtension: "Workflow"))
    }
}
