import AppKit
import CoreGraphics
import Foundation
import LumakeyCore
import os

func testV070CleanPerf() throws {
    let sharedPrefs = SystemDisplayPreferences.shared
    check(
        sharedPrefs.reduceTransparency == NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
        "SystemDisplayPreferences.shared.reduceTransparency matches NSWorkspace"
    )
    check(
        sharedPrefs.increaseContrast == NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
        "SystemDisplayPreferences.shared.increaseContrast matches NSWorkspace"
    )

    let customCenter = NotificationCenter()
    let mockFlagLock = OSAllocatedUnfairLock(initialState: SystemDisplayPreferences.Snapshot(reduceTransparency: false, increaseContrast: false))
    let isolatedPrefs = SystemDisplayPreferences(notificationCenter: customCenter) {
        mockFlagLock.withLock { $0 }
    }
    check(isolatedPrefs.reduceTransparency == false && isolatedPrefs.increaseContrast == false, "initial custom display prefs false")

    mockFlagLock.withLock { $0 = .init(reduceTransparency: true, increaseContrast: true) }
    check(isolatedPrefs.reduceTransparency == false, "cached O(1) value unchanged before accessibility notification fires")
    customCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    check(isolatedPrefs.reduceTransparency == true && isolatedPrefs.increaseContrast == true, "notification updates cached display prefs")

    DispatchQueue.concurrentPerform(iterations: 2_000) { idx in
        if idx == 1_000 { _ = isolatedPrefs.refresh() }
        _ = isolatedPrefs.snapshot
    }
    check(isolatedPrefs.snapshot == .init(reduceTransparency: true, increaseContrast: true), "concurrent O(1) reads remain thread-safe")

    let tmpRoot = try makeTempDir("v070-gif-cache")
    defer { try? FileManager.default.removeItem(at: tmpRoot) }
    let gifDir = tmpRoot.appendingPathComponent("lumakey-gifs", isDirectory: true)
    let capDir = tmpRoot.appendingPathComponent("lumakey-captures", isDirectory: true)
    let supDir = tmpRoot.appendingPathComponent("Support", isDirectory: true)
    try FileManager.default.createDirectory(at: gifDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: capDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: supDir, withIntermediateDirectories: true)

    let purgeGif = gifDir.appendingPathComponent("rec-1.gif")
    let keepGif = gifDir.appendingPathComponent("rec-pinned.gif")
    let subShot = capDir.appendingPathComponent("lumakey-pin-sub.png")
    let cfgFile = supDir.appendingPathComponent("settings.json")
    try Data(repeating: 0x47, count: 400).write(to: purgeGif)
    try Data(repeating: 0x49, count: 200).write(to: keepGif)
    try Data(repeating: 0x89, count: 100).write(to: subShot)
    try Data(repeating: 0x7B, count: 64).write(to: cfgFile)

    let inspected = AppCacheService.inspectAll(tempRoot: tmpRoot, appSupportRoot: supDir)
    let gifBucket = inspected.buckets.first(where: { $0.kind == .gifCaptures })
    check(gifBucket != nil && gifBucket?.isProtected == false, ".gifCaptures bucket registered and purgeable")
    check(gifBucket?.fileCount == 2 && gifBucket?.sizeBytes == 600, ".gifCaptures measures lumakey-gifs accurately")
    check(inspected.purgeableBytes == 700 && inspected.protectedBytes == 64, "inspectAll totals include .gifCaptures and lumakey-captures")

    let freedGif = AppCacheService.clearBucket(.gifCaptures, protectedURLs: [keepGif], tempRoot: tmpRoot)
    check(freedGif == 400, "clearBucket(.gifCaptures) frees unprotected GIF bytes")
    check(!FileManager.default.fileExists(atPath: purgeGif.path), "unprotected GIF deleted")
    check(FileManager.default.fileExists(atPath: keepGif.path), "protected GIF preserved")
    check(FileManager.default.fileExists(atPath: subShot.path), "other cache buckets untouched by isolated .gifCaptures clear")

    let freedRest = AppCacheService.clearAllPurgeable(protectedURLs: [keepGif], tempRoot: tmpRoot)
    check(freedRest == 100 && FileManager.default.fileExists(atPath: cfgFile.path), "clearAllPurgeable cleans remaining temp files safely")

    check(EverythingIndex.hasPackageSuffix("Xcode.app") && EverythingIndex.hasPackageSuffix("Core.FRAMEWORK"), "hasPackageSuffix case-insensitive UTF-8")
    check(!EverythingIndex.hasPackageSuffix("Documents") && !EverythingIndex.hasPackageSuffix("a"), "hasPackageSuffix rejects plain folders")
    check(EverythingIndex.extractExtensionLower(fromName: "Clip.MP4") == "mp4", "extractExtensionLower folds ASCII")
    check(EverythingIndex.extractExtensionLower(fromName: ".DS_Store") == "", "extractExtensionLower ignores leading-dot hidden files")
    check(EverythingIndex.extractExtensionLower(fromName: "归档.TAR.GZ") == "gz", "extractExtensionLower handles CJK stem with multi-dot")

    let idxRoot = tmpRoot.appendingPathComponent("idx-root", isDirectory: true)
    let nested = idxRoot.appendingPathComponent("Alpha/Beta/Gamma", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("1".utf8).write(to: idxRoot.appendingPathComponent("old_readme_backup.txt"))
    try Data("2".utf8).write(to: nested.appendingPathComponent("readme_guide.md"))
    try Data("3".utf8).write(to: nested.appendingPathComponent("README.md"))
    try Data("4".utf8).write(to: nested.appendingPathComponent("readme"))

    let idx = try EverythingIndex.build(rootURL: idxRoot)
    let ranked = idx.search(queryText: "readme", limit: 10)
    check(ranked.count == 4, "ranked search finds all 4 readme variants")
    check(ranked[0].name == "readme" && ranked[1].name == "README.md" && ranked[2].name == "readme_guide.md" && ranked[3].name == "old_readme_backup.txt",
          "EverythingIndex+Search ranks exact > stem > prefix > substring: got \(ranked.map(\.name))")
    check(ranked[0].relativeParentPath == "Alpha/Beta/Gamma", "zero-array relativeParent reconstructs multi-level path: \(ranked[0].relativeParentPath)")
    let pathHits = idx.search(queryText: "path:alpha/beta ext:md", limit: 10)
    check(pathHits.count == 2, "pathContains QueryNeedle matches multi-segment path case-insensitively")

    let crlfMarkdown = "---\r\ntitle: CleanPerf\r\n---\r\n# Main Title\r\n\r\n* * *\r\n> [!WARNING]\r\n> Watch line limits.\r\n\r\n3. Third start\r\n4. Fourth item\r\n\r\n| ColA | ColB |\r\n| :--- | ---: |\r\n| 1 | 2 |\r\n\r\n~~~bash\r\necho ok\r\n~~~\r\n"
    let blocks = MarkdownDocumentParser.parse(crlfMarkdown)
    check(blocks.count == 7, "CRLF Markdown parses all 7 blocks, got \(blocks.count)")
    check(MarkdownDocumentParser.headings(in: blocks) == [MarkdownHeadingItem(id: "h-2", level: 1, text: "Main Title")], "headings TOC preserved")
    check(blocks.contains(where: { if case .alert(_, .warning, ["Watch line limits."]) = $0 { return true }; return false }), "WARNING alert parsed")
    check(blocks.contains(where: { if case .orderedList(_, 3, ["Third start", "Fourth item"]) = $0 { return true }; return false }), "orderedList start=3 parsed")
    check(blocks.contains(where: { if case .codeBlock(_, "bash", "echo ok") = $0 { return true }; return false }), "tilde fenced codeBlock parsed")

    try MainActor.assumeIsolated {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("cleanperf-restore", forType: .string)
        let snap = PasteboardSnapshot.capture(from: pb)

        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 60, height: 40, bitsPerComponent: 8, bytesPerRow: 240, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.6, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        let img = ctx.makeImage()!
        let mosaicOut = try ScreenshotCompositor.renderCroppedImage(
            baseImage: img,
            screenBounds: CGRect(x: 0, y: 0, width: 60, height: 40),
            selectionRect: CGRect(x: 0, y: 0, width: 60, height: 40),
            annotations: [ScreenshotAnnotation(tool: .mosaic, color: AnnotationRGBColor.presets[0], strokeSize: .medium, points: [CGPoint(x: 15, y: 15), CGPoint(x: 20, y: 20)])]
        )
        check(ScreenshotCompositor.copyImageToPasteboard(mosaicOut, scale: 2.0, to: pb), "split ScreenshotPasteboardIO copies mosaic image")
        snap.restore(to: pb)
        check(pb.string(forType: .string) == "cleanperf-restore", "split PasteboardSnapshot restores string")
    }

    print("[ok] v0.7.0 CleanPerf: SystemDisplayPreferences + .gifCaptures + EverythingRank + Markdown + CompositorSplit")
}
