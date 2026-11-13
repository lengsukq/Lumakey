import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import LumakeyCore

@discardableResult
func check(_ condition: Bool, _ message: String) -> Bool {
    if !condition {
        fputs("FAILED: \(message)\n", stderr)
        exit(1)
    }
    return true
}

func makeTempDir(_ label: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-check-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func renderTextPNG(text: String, to url: URL) throws {
    let width = 480
    let height = 140
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 42, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    NSAttributedString(string: text, attributes: attrs).draw(at: NSPoint(x: 28, y: 44))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: url)
}

func testVolumeAndMedia() throws {
    check(VolumeInspector.classifyFormat(fsType: "ntfs", isReadOnly: true) == .ntfsReadOnly, "ntfs ro")
    check(VolumeInspector.classifyFormat(fsType: "macfuse", isReadOnly: false) == .ntfsFuseWritable, "fuse rw")
    check(VolumeInspector.inspect(url: URL(fileURLWithPath: "/")) != nil, "root volume statfs")
    check(LumakeyError.readOnlyVolume("TestNTFS").diagnostic.title.contains("只读"), "readonly volume diagnostic")
    check(LumakeySortOrder.ascending.toggled == .descending, "sort order toggle")

    let tmp = try makeTempDir("media")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let imgURL = tmp.appendingPathComponent("sample.png")
    try renderTextPNG(text: "LUMAKEY 2026", to: imgURL)
    let dims = MediaClassifier.readImageDimensions(at: imgURL)
    check(dims == CGSize(width: 480, height: 140), "image dimensions")
    check(MediaClassifier.makeThumbnail(at: imgURL, maxPixelSize: 120) != nil, "thumbnail generation")

    let vision = try VisionService.analyzeTextAndBarcodes(at: imgURL)
    check(vision.recognizedText.uppercased().contains("LUMAKEY"), "Vision OCR text recognized: '\(vision.recognizedText)'")
    print("[ok] VolumeInspector + MediaClassifier + VisionService OCR")
}

func testDirectoryAndBatchRename() throws {
    let tmp = try makeTempDir("rename")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let a = tmp.appendingPathComponent("a.txt")
    let b = tmp.appendingPathComponent("b.txt")
    try "hello".write(to: a, atomically: true, encoding: .utf8)
    try "world".write(to: b, atomically: true, encoding: .utf8)

    let hash = try DirectoryScanner.computeSHA256(for: a)
    check(hash.count == 64, "sha256 length")

    let scanned = try DirectoryScanner.sortEntries(
        DirectoryScanner.scanDirectory(at: tmp, includeHidden: false),
        by: .name,
        order: .ascending
    )
    check(scanned.count == 2, "scanned 2 files")

    let rule = BatchRenameRule(prefix: "v_", useIndexNumbering: true, startNumber: 1, zeroPadWidth: 2)
    let plan = BatchRenamePlanner.plan(entries: scanned, rule: rule)
    check(plan.allSatisfy { !$0.hasConflict }, "clean rename plan")
    try BatchRenamePlanner.apply(plan)
    check(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("v_a_01.txt").path), "renamed a")

    let collideRule = BatchRenameRule(findText: "a_01", replaceText: "b_02")
    let rescanned = try DirectoryScanner.scanDirectory(at: tmp, includeHidden: false)
    let badPlan = BatchRenamePlanner.plan(entries: rescanned, rule: collideRule)
    check(badPlan.contains(where: \.hasConflict), "collision detected")
    print("[ok] DirectoryScanner + BatchRenamePlanner")
}

func testEverythingLauncherUnitsAndClipboard() throws {
    let tmp = try makeTempDir("everything")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let rootA = tmp.appendingPathComponent("rootA", isDirectory: true)
    let rootB = tmp.appendingPathComponent("rootB", isDirectory: true)
    let sub = rootA.appendingPathComponent("src", isDirectory: true)
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
    try "let x = 1".write(to: sub.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
    try "".write(to: sub.appendingPathComponent("clip.mp4"), atomically: true, encoding: .utf8)
    try "".write(to: rootB.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)

    let multiIndex = try EverythingIndex.build(rootURLs: [rootA, rootB])
    check(multiIndex.nodes.count == 4, "multi-root indexed 4 nodes, got \(multiIndex.nodes.count)")
    check(multiIndex.search(queryText: "ext:swift path:src").first?.url.path.hasSuffix("rootA/src/App.swift") == true, "multi-root url resolution")
    check(multiIndex.search(queryText: "video: | folder:").count == 2, "dsl or clause")

    let py = PinyinHelper.convert("活动监视器")
    check(py.full == "huodongjianshiqi" && py.initials == "hdjsq", "pinyin conversion got \(py)")
    check(SafeMathEvaluator.evaluate("2 ^ 10") == "1024", "power math eval")
    check(SafeMathEvaluator.evaluate("0xff + 1") == "256", "hex math eval")
    check(SafeMathEvaluator.evaluate("((bad input))") == nil, "invalid math safe nil")

    check(UnitAndCommandEngine.evaluate("255 in hex")?.resultText == "0xFF", "dec to hex")
    check(UnitAndCommandEngine.evaluate("0xff in dec")?.resultText == "255", "hex to dec")
    check(UnitAndCommandEngine.evaluate("2048 mb to gb")?.resultText == "2 GB", "mb to gb")
    check(UnitAndCommandEngine.evaluate("30 c to f")?.resultText == "86 °F", "c to f")
    check(UnitAndCommandEngine.evaluate("10 km to mi")?.resultText.contains("6.214") == true, "km to mi")
    check(UnitAndCommandEngine.matchCommands(query: "x", volumes: []).isEmpty, "single-letter command no false match")

    let fakeApp = InstalledAppItem(name: "活动监视器", englishName: "Activity Monitor", url: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    let inlineFileHits = LauncherEngine.rankCandidates(query: "f ext:swift", apps: [fakeApp], plugins: [], everythingIndex: multiIndex)
    check(inlineFileHits.contains(where: { if case .fileHit = $0.kind { return true }; return false }), "inline launcher file hit")
    let zhHit = LauncherEngine.rankCandidates(query: "hdjsq", apps: [fakeApp], plugins: [])
    check(!zhHit.isEmpty, "localized pinyin initials match")

    check(ClipboardService.parseHexColor("#3478f6") == "#3478F6", "hex color normalization")
    let e1 = ClipboardEntry(title: "#3478F6", subtitle: "HEX", textValue: "#3478f6", isPinned: true, payloadKind: .colorHex("#3478F6"))
    let e2 = ClipboardEntry(title: "other", subtitle: "text", textValue: "hello", payloadKind: .text)
    let e1Again = ClipboardEntry(title: "#3478F6", subtitle: "HEX", textValue: "#3478f6", isPinned: false, payloadKind: .colorHex("#3478F6"))
    var list = ClipboardService.insert(e1, into: [])
    list = ClipboardService.insert(e2, into: list)
    list = ClipboardService.insert(e1Again, into: list)
    check(list.count == 2 && list.first?.isPinned == true, "clipboard dedupe preserves pin at top")
    print("[ok] EverythingIndex + UnitAndCommandEngine + ClipboardService + LauncherEngine")
}

func testPluginAndMCPSubprocess() throws {
    check(!PluginSystem.isSafePluginID("../escape"), "unsafe id rejected")
    let tmp = try makeTempDir("mcp-plugins")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let binDir = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
    let mcpURL = binDir.appendingPathComponent("lumakey-mcp")
    check(FileManager.default.isExecutableFile(atPath: mcpURL.path), "lumakey-mcp binary exists at \(mcpURL.path)")

    let process = Process()
    process.executableURL = mcpURL
    process.arguments = ["--plugins-dir", tmp.path]
    let inPipe = Pipe()
    let outPipe = Pipe()
    process.standardInput = inPipe
    process.standardOutput = outPipe
    try process.run()

    let requests: [String] = [
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
        #"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"lumakey://specs/plugin-v1"}}"#,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"lumakey_scaffold_plugin","arguments":{"id":"demo-echo","name":"Demo Echo","keywords":["echo"]}}}"#,
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"lumakey_validate_plugin","arguments":{"id":"demo-echo"}}}"#,
        #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"lumakey_run_plugin_test","arguments":{"id":"demo-echo","query":"ping"}}}"#
    ]
    let payload = (requests.joined(separator: "\n") + "\n").data(using: .utf8)!
    try inPipe.fileHandleForWriting.write(contentsOf: payload)
    try inPipe.fileHandleForWriting.close()
    process.waitUntilExit()
    check(process.terminationStatus == 0, "lumakey-mcp exited 0")

    let outString = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let lines = outString.split(separator: "\n").map(String.init)
    check(lines.count == 5, "expected 5 JSON-RPC responses, got \(lines.count)")

    func toolText(at lineIndex: Int) -> String {
        guard let data = lines[lineIndex].data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
        else { return "" }
        return text
    }

    check(lines[0].contains("lumakey-mcp"), "initialize response")
    check(lines[1].contains("Lumakey Plugin Specification"), "spec resource content")
    check(toolText(at: 2).contains("Scaffolded plugin 'demo-echo'"), "scaffold result: \(toolText(at: 2))")
    let validateText = toolText(at: 3)
    let validateObj = (try? JSONSerialization.jsonObject(with: Data(validateText.utf8)) as? [String: Any]) ?? [:]
    check((validateObj["valid"] as? Bool) == true, "scaffolded plugin validates cleanly, got: \(validateText)")
    check(toolText(at: 4).contains("[demo-echo] ok"), "script plugin executed via MCP, got: \(toolText(at: 4))")
    print("[ok] PluginSystem + real lumakey-mcp stdio JSON-RPC subprocess")
}

func testV03MarkdownOmniMosAndMemory() throws {
    check(MediaClassifier.classify(url: URL(fileURLWithPath: "/tmp/readme.md"), isDirectory: false) == .markdown, "md classifies as .markdown")
    check(MediaClassifier.classify(url: URL(fileURLWithPath: "/tmp/notes.markdown"), isDirectory: false) == .markdown, "markdown classifies as .markdown")
    check(MediaClassifier.classify(url: URL(fileURLWithPath: "/tmp/main.swift"), isDirectory: false) == .text, "swift classifies as .text")

    let sampleMD = """
    ---
    title: Lumakey v0.3
    author: Queensu
    ---

    # Heading One

    Hello **world** with `inline`.

    > [!TIP]
    > Smooth scroll enabled.

    - [x] Done task
    - [ ] Open task

    | Name | Kind |
    | --- | --- |
    | Mos | Mouse |

    ```swift
    let x = 42
    ```
    """
    let blocks = MarkdownDocumentParser.parse(sampleMD)
    check(blocks.contains(where: { if case .frontmatter = $0 { return true }; return false }), "markdown frontmatter parsed")
    check(blocks.contains(where: { if case .heading(_, 1, "Heading One") = $0 { return true }; return false }), "markdown H1 parsed")
    check(blocks.contains(where: { if case .alert(_, .tip, _) = $0 { return true }; return false }), "markdown tip callout parsed")
    check(blocks.contains(where: { if case .taskList = $0 { return true }; return false }), "markdown task list parsed")
    check(blocks.contains(where: { if case .table = $0 { return true }; return false }), "markdown table parsed")
    check(blocks.contains(where: { if case .codeBlock(_, "swift", _) = $0 { return true }; return false }), "markdown fenced code block parsed")
    check(MarkdownDocumentParser.headings(in: blocks).count == 1, "markdown heading TOC extraction")

    let tmp = try makeTempDir("v03-omni")
    defer { try? FileManager.default.removeItem(at: tmp) }
    try sampleMD.write(to: tmp.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    let index = try EverythingIndex.build(rootURLs: [tmp])
    let clip = ClipboardEntry(title: "readme snippet", subtitle: "text", textValue: "readme note", payloadKind: .text)
    let fakeApp = InstalledAppItem(name: "活动监视器", englishName: "Activity Monitor", url: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))

    let allHits = LauncherEngine.rankCandidates(
        query: "readme",
        filter: .all,
        apps: [fakeApp],
        plugins: [],
        clipboardItems: [clip],
        everythingIndex: index
    )
    check(allHits.contains(where: { if case .fileHit = $0.kind { return true }; return false }), "unified search matches files without f prefix")
    check(allHits.contains(where: { if case .clipboard = $0.kind { return true }; return false }), "unified search matches clipboard items")

    let mosCmds = UnitAndCommandEngine.matchCommands(query: "mos", volumes: [])
    check(mosCmds.contains(where: { $0.command == .toggleMosEnabled }), "mos command matched")

    let timeoutRes = try ProcessSupervisor.shared.run(
        executableURL: URL(fileURLWithPath: "/bin/sleep"),
        arguments: ["5"],
        timeoutSeconds: 0.25
    )
    check(timeoutRes.timedOut == true, "ProcessSupervisor kills timed-out subprocess")
    check(ProcessSupervisor.shared.activeCount == 0, "ProcessSupervisor clears active PIDs after termination")

    let mosURL = tmp.appendingPathComponent("mos-config.json")
    var cfg = MosConfig()
    cfg.enabled = true
    cfg.reverseWheelDirection = false
    cfg.stepPixels = 48
    cfg.excludedBundleIDs = ["com.microsoft.rdc.macos"]
    cfg.save(to: mosURL)
    let reloaded = MosConfig.load(from: mosURL)
    check(reloaded == cfg, "MosConfig JSON persistence roundtrip")
    MosEngine.shared.stopTapAndReleaseAll()
    check(MosEngine.shared.isTapActive == false, "MosEngine releases event tap cleanly")

    check(MemoryStats.currentPhysicalFootprintMB() > 0, "MemoryStats reports positive physical footprint")
    MemoryStats.reclaimFreeHeapPages()
    print("[ok] v0.3 Markdown + OmniSearch + ProcessSupervisor + Mos + MemoryStats")
}

func testV04ScreenshotCompositorAndFastIndex() throws {
    check(MediaClassifier.classifyExtension("md", isDirectory: false) == .markdown, "classifyExtension classifies md as markdown")
    check(MediaClassifier.classifyExtension("mp4", isDirectory: false) == .video, "classifyExtension classifies mp4 as video")

    let tmp = try makeTempDir("v04-fast")
    defer { try? FileManager.default.removeItem(at: tmp) }
    try "# Doc".write(to: tmp.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
    let index = try EverythingIndex.build(rootURLs: [tmp])
    let emptyHits = index.search(queryText: "", limit: 10)
    check(emptyHits.contains(where: { $0.name == "note.md" && FileManager.default.fileExists(atPath: $0.url.path) }), "EverythingIndex empty-query fast path returns valid URL")

    let width = 200
    let height = 120
    let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        check(false, "create synthetic screenshot CGContext")
        return
    }
    ctx.setFillColor(CGColor(srgbRed: 0x33 / 255.0, green: 0x66 / 255.0, blue: 0x99 / 255.0, alpha: 1.0))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let baseCG = ctx.makeImage() else {
        check(false, "extract CGImage from synthetic context")
        return
    }

    let bounds = CGRect(x: 0, y: 0, width: 200, height: 120)
    let hex = ScreenshotCompositor.samplePixelColor(in: baseCG, point: CGPoint(x: 50, y: 40), screenBounds: bounds)
    check(hex == "#336699", "samplePixelColor reads exact #RRGGBB pixel value (got \(hex))")

    let sel = CGRect(x: 20, y: 20, width: 100, height: 80)
    let red = AnnotationRGBColor.presets[0]
    let blue = AnnotationRGBColor.presets[4]
    let annotations: [ScreenshotAnnotation] = [
        ScreenshotAnnotation(tool: .rect, color: red, strokeSize: .small, points: [CGPoint(x: 25, y: 25), CGPoint(x: 70, y: 60)]),
        ScreenshotAnnotation(tool: .ellipse, color: blue, strokeSize: .medium, points: [CGPoint(x: 40, y: 30), CGPoint(x: 100, y: 80)]),
        ScreenshotAnnotation(tool: .arrow, color: red, strokeSize: .medium, points: [CGPoint(x: 30, y: 80), CGPoint(x: 90, y: 35)]),
        ScreenshotAnnotation(tool: .pen, color: red, strokeSize: .small, points: [CGPoint(x: 28, y: 40), CGPoint(x: 45, y: 55), CGPoint(x: 62, y: 45)]),
        ScreenshotAnnotation(tool: .highlighter, color: AnnotationRGBColor.presets[2], strokeSize: .large, points: [CGPoint(x: 35, y: 70), CGPoint(x: 105, y: 70)]),
        ScreenshotAnnotation(tool: .mosaic, color: red, strokeSize: .medium, points: [CGPoint(x: 60, y: 50), CGPoint(x: 75, y: 55)]),
        ScreenshotAnnotation(tool: .counter, color: red, strokeSize: .medium, points: [CGPoint(x: 85, y: 40)], counterIndex: 1),
        ScreenshotAnnotation(tool: .text, color: blue, strokeSize: .small, points: [CGPoint(x: 30, y: 24)], text: "Lumakey")
    ]
    let cropped = try ScreenshotCompositor.renderCroppedImage(
        baseImage: baseCG,
        screenBounds: bounds,
        selectionRect: sel,
        annotations: annotations
    )
    check(cropped.width == 100 && cropped.height == 80, "renderCroppedImage produces exact cropped dimensions")

    let outURL = try ScreenshotCompositor.saveTempCapture(cropped)
    defer { try? FileManager.default.removeItem(at: outURL) }
    check(FileManager.default.fileExists(atPath: outURL.path), "saveTempCapture writes PNG file")
    let reloaded = NSImage(contentsOf: outURL)
    check(reloaded != nil && Int(reloaded!.size.width) >= 100, "saved screenshot PNG loads back cleanly via NSImage")

    let pix = ScreenshotCompositor.makePixelatedPreview(from: baseCG, cellPixelSize: 10)
    check(pix != nil && pix!.width == 20 && pix!.height == 12, "makePixelatedPreview downsamples CGImage cleanly")

    let ocrURL = tmp.appendingPathComponent("ocr-fast-check.png")
    try renderTextPNG(text: "测试识字 Lumakey 2026", to: ocrURL)
    let ocrStarted = Date()
    let ocrResult = try VisionService.analyzeTextAndBarcodes(at: ocrURL)
    let ocrElapsed = Date().timeIntervalSince(ocrStarted)
    check(ocrElapsed < 3.0, "Vision OCR finishes rapidly without ANE stall (elapsed: \(String(format: "%.2f", ocrElapsed))s)")
    check(ocrResult.recognizedText.contains("Lumakey"), "Vision OCR recognizes Chinese + English text cleanly")
    print("[ok] v0.4.1 ScreenshotCompositor + Fast CPU Vision OCR (\(String(format: "%.2f", ocrElapsed))s) + Fast Index")
}

func testV05SystemMonitor() throws {
    let sampler = SystemMonitorSampler()
    _ = sampler.sample()
    usleep(35_000)
    var snap = sampler.sample()
    for _ in 0..<15 {
        snap = sampler.sample()
    }
    check(snap.memoryTotalBytes > 1_000_000_000, "system monitor reads positive total physical RAM")
    check(snap.memoryUsedBytes > 0 && snap.memoryUsedBytes <= snap.memoryTotalBytes, "system monitor used memory bounded")
    check(snap.cpuTotalPercent >= 0 && snap.cpuTotalPercent <= 100.0, "system monitor CPU percent in 0...100")
    check(snap.estimatedFrequencyGHz > 0.2 && snap.maxFrequencyGHz >= snap.estimatedFrequencyGHz, "system monitor DVFS frequency valid")
    check(!snap.chipBrand.isEmpty, "system monitor chip brand non-empty")
    check(snap.systemWatts >= 0, "system monitor watts non-negative")
    check(snap.netDownBytesPerSec >= 0 && snap.netUpBytesPerSec >= 0, "system monitor net rate non-negative")
    check(snap.diskTotalGB > 1.0, "system monitor reads positive root volume total GB")
    check(!snap.menuBarCompactText.isEmpty, "system monitor formats menu bar readout")

    let tmp = try makeTempDir("v05-telemetry")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let cfgURL = tmp.appendingPathComponent("telemetry.json")
    var cfg = SystemMonitorConfig()
    cfg.displayMode = .edgeAutoHide
    cfg.dockedEdgeRaw = "right"
    cfg.showInMenuBar = false
    cfg.save(to: cfgURL)
    let loaded = SystemMonitorConfig.load(from: cfgURL)
    check(loaded == cfg, "SystemMonitorConfig JSON persistence roundtrip")

    let monCmds = UnitAndCommandEngine.matchCommands(query: "监控", volumes: [])
    check(monCmds.contains(where: { $0.command == .toggleSystemMonitor }), "monitor command matched")
    print("[ok] v0.5 SystemMonitorSampler (CPU/Freq/Mem/Watts/Net/Disk) + Config + Command")
}

func testV051MultiRootEverythingWorkspaceAndDefaults() throws {
    let defaultTelemetry = SystemMonitorConfig()
    check(defaultTelemetry.floatingEnabled == false, "fresh install floating monitor defaults OFF")
    check(defaultTelemetry.showInMenuBar == false, "fresh install menu bar telemetry defaults OFF")
    check(MosConfig().enabled == false, "fresh install Mos defaults OFF")

    var metricCfg = SystemMonitorConfig()
    metricCfg.menuShowCPU = true
    metricCfg.menuShowFreq = true
    metricCfg.menuShowMemory = true
    metricCfg.menuShowPower = false
    metricCfg.menuShowNet = false
    var sampleSnap = SystemTelemetrySnapshot.placeholder
    sampleSnap.cpuTotalPercent = 24
    sampleSnap.estimatedFrequencyGHz = 3.21
    sampleSnap.memoryPercent = 58
    let barText = metricCfg.formatMenuBarText(from: sampleSnap)
    check(barText.contains("24%") && barText.contains("3.21G") && barText.contains("M58%"), "custom menu bar telemetry metrics formatted")

    let tmp = try makeTempDir("v051-multi-posix")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let rootA = tmp.appendingPathComponent("LocalHome")
    let rootB = tmp.appendingPathComponent("ExternalDisk")
    try FileManager.default.createDirectory(at: rootA.appendingPathComponent("Docs"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: rootB.appendingPathComponent("Movies"), withIntermediateDirectories: true)
    try "hello world".write(to: rootA.appendingPathComponent("Docs/guide.md"), atomically: true, encoding: .utf8)
    try Data(repeating: 0xAB, count: 512).write(to: rootB.appendingPathComponent("Movies/clip.mp4"))

    let idxA = try EverythingIndex.build(rootURLs: [rootA], maxNodes: 1000)
    let idxB = try EverythingIndex.build(rootURLs: [rootB], maxNodes: 1000)
    let merged = idxA.merging(idxB)
    let videoHits = merged.search(queryText: "video: path:ExternalDisk", limit: 10)
    check(videoHits.count == 1 && videoHits[0].name == "clip.mp4" && videoHits[0].sizeBytes == 512, "merged POSIX EverythingIndex finds external volume video and resolves lazy stat size")

    let entries = try DirectoryScanner.scanDirectory(at: rootB, includeHidden: false)
        + [FileEntry(url: rootA.appendingPathComponent("Docs/guide.md"), name: "guide.md", isDirectory: false, sizeBytes: 11, modifiedAt: Date(), createdAt: Date().addingTimeInterval(-100), extensionLowercased: "md", mediaKind: .markdown)]
    let sortedExt = DirectoryScanner.sortEntries(entries, by: .ext, order: .ascending, foldersFirst: false)
    check(sortedExt.first?.name == "Movies", "sort by ext with foldersFirst=false sorts directories by empty extension first")
    check(WorkspaceMediaFilter.document.matches(entries.last!), "WorkspaceMediaFilter.document matches markdown entry")
    check(!WorkspaceMediaFilter.image.matches(entries.last!), "WorkspaceMediaFilter.image excludes markdown entry")
    print("[ok] v0.5.1 Default-OFF Telemetry + POSIX Multi-Root Everything + Workspace Sort/Filter")
}

func testV053VideoCompatAndCodeSigning() throws {
    let tmp = try makeTempDir("v053-video")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let mp4URL = tmp.appendingPathComponent("sample-hev1.mp4")

    // Build synthetic MP4: [ftyp(16)] + [moov with hev1 sample entry] + [mdat with fake hev1 bytes]
    var ftyp = Data([0x00, 0x00, 0x00, 0x10]) + Data("ftypisom".utf8) + Data([0, 0, 0, 0])
    let moovPayload = Data(repeating: 0x00, count: 12)
        + Data([0x68, 0x65, 0x76, 0x31, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01])
        + Data(repeating: 0x11, count: 16)
    let moovSize = UInt32(8 + moovPayload.count).bigEndian
    let moov = withUnsafeBytes(of: moovSize) { Data($0) } + Data("moov".utf8) + moovPayload
    let mdatPayload = Data([0x68, 0x65, 0x76, 0x31, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) + Data(repeating: 0xAA, count: 24)
    let mdatSize = UInt32(8 + mdatPayload.count).bigEndian
    let mdat = withUnsafeBytes(of: mdatSize) { Data($0) } + Data("mdat".utf8) + mdatPayload

    ftyp.append(moov)
    ftyp.append(mdat)
    try ftyp.write(to: mp4URL)

    let scan = Hev1ResourceLoader.findHev1SampleEntryOffsets(in: mp4URL)
    let expectedOffset = Int64(16 + 8 + 12)
    check(scan.fileSize == Int64(ftyp.count), "Hev1ResourceLoader reads exact MP4 fileSize")
    check(scan.offsets == [expectedOffset], "Hev1ResourceLoader finds moov hev1 sample entry and ignores mdat bytes")

    let signStatus = CodeSigningInspector.inspect(bundleURL: URL(fileURLWithPath: "/System/Applications/Calculator.app"))
    check(!signStatus.badgeTitle.isEmpty && !signStatus.bundleIdentifier.isEmpty, "CodeSigningInspector inspects macOS app bundle")
    print("[ok] v0.5.3 Hev1ResourceLoader Zero-Copy Patch + CodeSigningInspector")
}

func testV060NetworkTrafficAndAppCache() throws {
    let csv1 = """
    ,interface,state,bytes_in,bytes_out,
    apsd.405,,,5519,10159,
    tcp4 198.18.0.1:58910<->17.57.145.26:5223,utun1024,Established,5519,10159,
    Safari.888,,,205000,45000,
    tcp4 192.168.1.5:51234<->142.250.190.78:443,en1,Established,205000,45000,
    launchd.1,,,0,0,
    tcp4 *:445<->*:*,,Listen,,,
    """
    let csv2 = """
    ,interface,state,bytes_in,bytes_out,
    apsd.405,,,5519,10159,
    tcp4 198.18.0.1:58910<->17.57.145.26:5223,utun1024,Established,5519,10159,
    Safari.888,,,307400,65480,
    tcp4 192.168.1.5:51234<->142.250.190.78:443,en1,Established,307400,65480,
    launchd.1,,,0,0,
    tcp4 *:445<->*:*,,Listen,,,
    """
    let pass1 = NetworkTrafficParser.parseNettopCSV(csv1, previous: [:], elapsed: 0) { _, name in
        (name, nil, nil)
    }
    let pass2 = NetworkTrafficParser.parseNettopCSV(csv2, previous: pass1.counters, elapsed: 2.0) { _, name in
        (name == "Safari" ? "Safari" : name, nil, nil)
    }
    check(pass2.snapshot.processes.count == 3, "parseNettopCSV parses all 3 processes")
    check(pass2.snapshot.externalHostCount == 2, "parseNettopCSV detects 2 unique external hosts")
    if let safari = pass2.snapshot.processes.first(where: { $0.pid == 888 }) {
        check(abs(safari.downBytesPerSec - 51_200) < 1.0, "Safari delta download rate matches 51200 B/s")
        check(abs(safari.upBytesPerSec - 10_240) < 1.0, "Safari delta upload rate matches 10240 B/s")
        check(safari.connections.first?.serviceTag == "HTTPS", "Safari :443 tagged as HTTPS")
    } else {
        check(false, "Safari process parsed")
    }
    if let apsd = pass2.snapshot.processes.first(where: { $0.pid == 405 }) {
        check(apsd.connections.first?.serviceTag == "TUN · Apple 推送", "utun :5223 tagged as TUN · Apple 推送")
    } else {
        check(false, "apsd process parsed")
    }
    if let launchd = pass2.snapshot.processes.first(where: { $0.pid == 1 }) {
        check(launchd.connections.first?.isListening == true && launchd.connections.first?.serviceTag == "端口监听", "Listen socket tagged correctly")
    } else {
        check(false, "launchd process parsed")
    }

    let liveTraffic = NetworkTrafficSampler().sample()
    check(!liveTraffic.processes.isEmpty, "live NetworkTrafficSampler collects host sockets without root")

    let tmpRoot = try makeTempDir("v060-cache")
    defer { try? FileManager.default.removeItem(at: tmpRoot) }
    let clipDir = tmpRoot.appendingPathComponent("lumakey-clipboard", isDirectory: true)
    let cinemaDir = tmpRoot.appendingPathComponent("lumakey-cinema", isDirectory: true)
    let supportDir = tmpRoot.appendingPathComponent("Support", isDirectory: true)
    try FileManager.default.createDirectory(at: clipDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: cinemaDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

    let purgeClip = clipDir.appendingPathComponent("a.png")
    let keepClip = clipDir.appendingPathComponent("keep.png")
    let pinFile = tmpRoot.appendingPathComponent("lumakey-pin-1.png")
    let remuxFile = cinemaDir.appendingPathComponent("remux.mp4")
    let configFile = supportDir.appendingPathComponent("mos-config.json")
    try Data(repeating: 1, count: 128).write(to: purgeClip)
    try Data(repeating: 2, count: 64).write(to: keepClip)
    try Data(repeating: 3, count: 256).write(to: pinFile)
    try Data(repeating: 4, count: 512).write(to: remuxFile)
    try Data(repeating: 5, count: 32).write(to: configFile)

    let before = AppCacheService.inspectAll(tempRoot: tmpRoot, appSupportRoot: supportDir, inMemoryEstimatedBytes: 1024, inMemoryItemCount: 5)
    check(before.purgeableBytes == 128 + 64 + 256 + 512, "AppCacheService sums purgeable buckets accurately")
    check(before.protectedBytes == 32, "AppCacheService separates protected config bytes")

    let freed = AppCacheService.clearAllPurgeable(protectedURLs: [keepClip], tempRoot: tmpRoot)
    check(freed == 128 + 256 + 512, "clearAllPurgeable removes only non-protected temp caches")
    check(!FileManager.default.fileExists(atPath: purgeClip.path), "unpinned clipboard temp removed")
    check(FileManager.default.fileExists(atPath: keepClip.path), "pinned clipboard file preserved")
    check(FileManager.default.fileExists(atPath: configFile.path), "AppSupport config preserved")

    let netCmds = UnitAndCommandEngine.matchCommands(query: "流量", volumes: [])
    check(netCmds.contains(where: { $0.command == .openNetworkMonitor }), "traffic command matches openNetworkMonitor")
    let cacheCmds = UnitAndCommandEngine.matchCommands(query: "缓存", volumes: [])
    check(cacheCmds.contains(where: { $0.command == .openCacheManager }), "cache command matches openCacheManager")
    print("[ok] v0.6.0 NetworkTrafficParser/Sampler + AppCacheService + Commands")
}

func testV061PreviewAutoPause() {
    let player = AVPlayer()
    let token = UUID()
    PreviewPlaybackRegistry.shared.register(token: token, player: player)
    check(PreviewPlaybackRegistry.shared.activeCount >= 1, "PreviewPlaybackRegistry tracks active inline AVPlayer")
    player.play()
    let ep0 = PreviewPlaybackRegistry.shared.pauseEpoch
    PreviewPlaybackRegistry.shared.pauseAll()
    check(player.rate == 0, "PreviewPlaybackRegistry.pauseAll() pauses registered AVPlayer")
    check(player.timeControlStatus == .paused, "AVPlayer enters .paused timeControlStatus")
    check(PreviewPlaybackRegistry.shared.pauseEpoch == ep0 + 1, "PreviewPlaybackRegistry increments pauseEpoch")
    PreviewPlaybackRegistry.shared.unregister(token: token)
    check(PreviewPlaybackRegistry.shared.activeCount == 0, "PreviewPlaybackRegistry unregisters dismantled player")
    print("[ok] v0.6.1 PreviewPlaybackRegistry Auto-Pause")
}

func testV062SystemPulseEdgeOrientation() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let topFrame = CGRect(x: 520, y: 850, width: 356, height: 34)
    let topEdge = PulseDockEdge.detectSnapEdge(frame: topFrame, visibleFrame: screen)
    check(topEdge == .top, "detectSnapEdge returns .top when near top screen edge")
    check(topEdge.isHorizontalStrip && !topEdge.isVerticalColumn, ".top renders horizontally")

    let leftFrame = CGRect(x: 10, y: 400, width: 58, height: 182)
    let leftEdge = PulseDockEdge.detectSnapEdge(frame: leftFrame, visibleFrame: screen)
    check(leftEdge == .left && leftEdge.isVerticalColumn, "detectSnapEdge returns vertical .left")

    let rightFrame = CGRect(x: 1370, y: 400, width: 58, height: 182)
    let rightEdge = PulseDockEdge.detectSnapEdge(frame: rightFrame, visibleFrame: screen)
    check(rightEdge == .right && rightEdge.isVerticalColumn, "detectSnapEdge returns vertical .right")

    let centerFrame = CGRect(x: 560, y: 400, width: 354, height: 318)
    let centerEdge = PulseDockEdge.detectSnapEdge(frame: centerFrame, visibleFrame: screen)
    check(centerEdge == .none && centerEdge.isHorizontalStrip, "center desktop stays unlocked .none")

    let nearestTop = PulseDockEdge.nearestEdge(for: CGRect(x: 680, y: 780, width: 100, height: 100), visibleFrame: screen)
    check(nearestTop == .top, "nearestEdge detects top edge when closest to top")
    print("[ok] v0.6.2 PulseDockEdge Top Horizontal & Side Vertical Orientation")
}

func testV063BinarySnapshotFSEventsAndDirCache() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("lumakey-v063-\(UUID().uuidString)", isDirectory: true)
    let cacheDir = root.appendingPathComponent(".cache-dir", isDirectory: true)
    let subDir = root.appendingPathComponent("src", isDirectory: true)
    try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    try Data("print(1)\n".utf8).write(to: subDir.appendingPathComponent("hello.swift"))
    let built = try EverythingIndex.build(rootURL: root, maxNodes: 1000)
    check(built.search(queryText: "hello.swift").count == 1, "initial index finds hello.swift")

    let savedURL = EverythingSnapshotStore.save(built, scopeKey: "v063-unit", cacheDirectory: cacheDir)
    check(savedURL != nil && fm.fileExists(atPath: savedURL!.path), "EverythingSnapshotStore saves binary .lmkyidx file")

    let loaded = EverythingSnapshotStore.load(scopeKey: "v063-unit", expectedRoots: [root], cacheDirectory: cacheDir)
    check(loaded != nil, "EverythingSnapshotStore loads snapshot via mmap")
    check(loaded?.nodes.count == built.nodes.count, "loaded snapshot preserves exact node count")
    check(loaded?.search(queryText: "hello.swift").count == 1, "mmap-loaded snapshot serves search hits")
    check(
        EverythingSnapshotStore.load(
            scopeKey: "v063-unit", expectedRoots: [root.appendingPathComponent("other")], cacheDirectory: cacheDir
        ) == nil,
        "snapshot rejects mismatched expectedRoots"
    )
    check(
        EverythingSnapshotStore.load(
            scopeKey: "v063-unit", expectedRoots: [root], maxAgeSeconds: -1, cacheDirectory: cacheDir
        ) == nil,
        "snapshot rejects expired snapshot"
    )

    // Test AppCacheService .diskIndexSnapshot reporting + isolated clearing
    let emptyTmp = root.appendingPathComponent("empty-tmp", isDirectory: true)
    let cacheBefore = AppCacheService.inspectAll(tempRoot: emptyTmp, indexCacheRoot: cacheDir)
    let idxBucket = cacheBefore.buckets.first(where: { $0.kind == .diskIndexSnapshot })
    check((idxBucket?.sizeBytes ?? 0) > 0, ".diskIndexSnapshot reports persisted snapshot size")
    let freed = AppCacheService.clearBucket(.diskIndexSnapshot, tempRoot: emptyTmp, indexCacheRoot: cacheDir)
    check(freed > 0, "clearing .diskIndexSnapshot deletes .lmkyidx snapshot files")

    // Test incremental FSEvent directory update with resolved (/private/var) path matching /var root
    let newSub = root.appendingPathComponent("docs", isDirectory: true)
    try fm.createDirectory(at: newSub, withIntermediateDirectories: true)
    try Data("# guide".utf8).write(to: newSub.appendingPathComponent("guide.md"))
    try Data("fn main() {}".utf8).write(to: subDir.appendingPathComponent("live_add.rs"))
    let resolvedRootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
    let resolvedSubPath = subDir.resolvingSymlinksInPath().standardizedFileURL.path
    let updated = built.applyingFSEventDirectories([resolvedRootPath, resolvedSubPath])
    check(updated.search(queryText: "live_add.rs").count == 1, "incremental FSEvent sync adds new file in existing folder")
    check(updated.search(queryText: "guide.md").count == 1, "incremental FSEvent sync scans newly created subfolder")

    try fm.removeItem(at: subDir.appendingPathComponent("live_add.rs"))
    let afterDelete = updated.applyingFSEventDirectories([resolvedSubPath])
    check(afterDelete.search(queryText: "live_add.rs").isEmpty, "incremental FSEvent sync removes deleted file")

    // Test live EverythingFSEventWatcher callback
    let watchDir = root.appendingPathComponent("watch-live", isDirectory: true)
    try fm.createDirectory(at: watchDir, withIntermediateDirectories: true)
    let sem = DispatchSemaphore(value: 0)
    let watcher = EverythingFSEventWatcher(roots: [watchDir], debounceInterval: 0.25) { dirs in
        if !dirs.isEmpty { sem.signal() }
    }
    check(watcher != nil, "EverythingFSEventWatcher initializes on existing directory")
    try Data("x".utf8).write(to: watchDir.appendingPathComponent("probe.txt"))
    let waitRes = sem.wait(timeout: .now() + 4.0)
    watcher?.stop()
    check(waitRes == .success, "EverythingFSEventWatcher delivers live filesystem event")

    // Test DirectoryScanner skipExtendedTags + directoryModificationDate + WorkspaceDirectoryCache LRU
    let scannedFast = try DirectoryScanner.scanDirectory(at: subDir, includeHidden: false, skipExtendedTags: true)
    check(scannedFast.contains(where: { $0.name == "hello.swift" && $0.tags.isEmpty }), "skipExtendedTags skips xattr tags")
    check(DirectoryScanner.directoryModificationDate(at: subDir) != nil, "directoryModificationDate returns POSIX stat mtime")

    let dirCache = WorkspaceDirectoryCache(maxEntries: 2)
    let summary = VolumeInspector.inspect(url: subDir)
    dirCache.store(entries: scannedFast, volumeSummary: summary, for: subDir, includeHidden: false, directoryMTime: Date())
    dirCache.store(entries: [], volumeSummary: summary, for: newSub, includeHidden: false, directoryMTime: Date())
    dirCache.store(entries: [], volumeSummary: summary, for: watchDir, includeHidden: false, directoryMTime: Date())
    check(dirCache.count == 2, "WorkspaceDirectoryCache enforces bounded LRU capacity")
    check(dirCache.lookup(for: subDir, includeHidden: false) == nil, "WorkspaceDirectoryCache evicts least recently used dir")
    check(dirCache.lookup(for: watchDir, includeHidden: false) != nil, "WorkspaceDirectoryCache retains hot dir")
    dirCache.trimKeepingRecent(1)
    check(dirCache.count == 1, "WorkspaceDirectoryCache.trimKeepingRecent keeps bounded count")
    dirCache.clear()
    check(dirCache.count == 0, "WorkspaceDirectoryCache.clear empties cache")
    print("[ok] v0.6.3 Binary mmap Snapshot, FSEvents Incremental Index & Workspace Directory Cache")
}

func testV064ScreenshotAutoPasteboardAndRestore() throws {
    try MainActor.assumeIsolated {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }

        pb.clearContents()
        pb.setString("keep-my-previous-text", forType: .string)

        let backup = PasteboardSnapshot.capture(from: pb)

        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 320,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            check(false, "create CGContext for v0.6.4 pasteboard test")
            return
        }
        ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.52, blue: 0.94, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        guard let cgImage = ctx.makeImage() else {
            check(false, "create CGImage for v0.6.4 pasteboard test")
            return
        }

        let copyOK = ScreenshotCompositor.copyImageToPasteboard(cgImage, scale: 2.0, to: pb)
        check(copyOK, "copyImageToPasteboard returns true")
        check(pb.data(forType: .png) != nil, "pasteboard contains PNG data")
        check(pb.data(forType: .tiff) != nil, "pasteboard contains TIFF data")
        check(NSImage(pasteboard: pb)?.size == NSSize(width: 40, height: 30), "pasteboard NSImage preserves Retina point size")

        let clipEntry = ClipboardService.captureCurrent(from: pb)
        if let clipEntry, case .image = clipEntry.payloadKind {
            ClipboardService.removeTempFiles(for: [clipEntry])
        } else {
            check(false, "ClipboardService captures copied screenshot image")
        }

        let tmpDir = try makeTempDir("v064-pb")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let fileURL = tmpDir.appendingPathComponent("shot.png")
        try ScreenshotCompositor.writePNG(cgImage, to: fileURL)
        pb.clearContents()
        let fileCopyOK = ScreenshotCompositor.copyImageFileToPasteboard(at: fileURL, to: pb)
        check(fileCopyOK && pb.data(forType: .png) != nil && pb.data(forType: .tiff) != nil, "copyImageFileToPasteboard writes PNG and TIFF")

        backup.restore(to: pb)
        check(pb.string(forType: .string) == "keep-my-previous-text", "PasteboardSnapshot restores previous text on cancel")
        check(pb.data(forType: .png) == nil, "PasteboardSnapshot removes transient screenshot PNG on restore")
        print("[ok] v0.6.4 Screenshot Auto-Pasteboard Dual-Format & Cancel Restore")
    }
}

func testV065PerformanceCompactIndexHeaderAndFormatters() throws {
    let strideBytes = MemoryLayout<IndexedNode>.stride
    check(strideBytes <= 32, "IndexedNode stride is compact (\(strideBytes) B <= 32 B)")

    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("lumakey-v065-\(UUID().uuidString)", isDirectory: true)
    let cacheDir = root.appendingPathComponent("idx-cache", isDirectory: true)
    let subDir = root.appendingPathComponent("docs", isDirectory: true)
    try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    try Data("pdf".utf8).write(to: subDir.appendingPathComponent("2026年度总结Report.pdf"))
    try Data("cafe".utf8).write(to: subDir.appendingPathComponent("Café_Notes.md"))

    let idx = try EverythingIndex.build(rootURLs: [subDir], maxNodes: 500)
    check(idx.nodes.count == 2, "indexed 2 unicode/mixed-case files")
    check(idx.search(queryText: "report").count == 1, "zero-alloc UTF8 query matches ASCII case-insensitively")
    check(idx.search(queryText: "年度").count == 1, "zero-alloc UTF8 query matches CJK")
    check(idx.search(queryText: "café").count == 1 && idx.search(queryText: "CAFÉ").count == 1, "non-ASCII fallback matches accented uppercase/lowercase")
    check(idx.search(queryText: "ext:pdf;md !pdf").count == 1, "ext + negated DSL works without stored ext strings")

    let saved = EverythingSnapshotStore.save(idx, scopeKey: "v065-perf", cacheDirectory: cacheDir)
    check(saved != nil, "LMKYIDX2 snapshot saves cleanly")
    let header = EverythingSnapshotStore.readHeaderMetadata(scopeKey: "v065-perf", expectedRoots: [subDir], cacheDirectory: cacheDir)
    check(header?.nodeCount == 2, "O(1) readHeaderMetadata reads exact nodeCount without full load")
    let reloaded = EverythingSnapshotStore.load(scopeKey: "v065-perf", expectedRoots: [subDir], cacheDirectory: cacheDir)
    check(reloaded?.search(queryText: "report").count == 1, "LMKYIDX2 load preserves search fidelity")

    check(FastFormatters.formatFileBytes(512) == "512 B", "FastFormatters formats sub-KB bytes")
    check(FastFormatters.formatFileBytes(2_500_000) == "2.5 MB", "FastFormatters formats MB")
    let dateStr = FastFormatters.formatModificationDate(Date(timeIntervalSince1970: 1_700_000_000))
    check(dateStr.count == 16 && dateStr.contains("-"), "FastFormatters formats local timestamp: \(dateStr)")

    let appItem = InstalledAppItem(name: "访达", englishName: "Finder", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
    check(appItem.englishNameLowercased == "finder" && appItem.nameLowercased == "访达", "InstalledAppItem precomputes lowercased names")
    let manifest = PluginManifest(id: "fast-plug", name: "NetTool", version: "1.0.0", description: "Probe Ports", mode: .script, keywords: ["Net", "PORT"], entry: "run.sh")
    let desc = PluginDescriptor(id: "fast-plug", directoryURL: subDir, manifest: manifest, validationIssues: [])
    check(desc.nameLowercased == "nettool" && desc.keywordsLowercased == ["net", "port"], "PluginDescriptor precomputes lowercased fields")
    print("[ok] v0.6.5 Compact IndexedNode (\(strideBytes)B) + LMKYIDX2 O(1) Header + UTF8 Query + FastFormatters")
}

do {
    try testVolumeAndMedia()
    try testDirectoryAndBatchRename()
    try testEverythingLauncherUnitsAndClipboard()
    try testPluginAndMCPSubprocess()
    try testV03MarkdownOmniMosAndMemory()
    try testV04ScreenshotCompositorAndFastIndex()
    try testV05SystemMonitor()
    try testV051MultiRootEverythingWorkspaceAndDefaults()
    try testV053VideoCompatAndCodeSigning()
    try testV060NetworkTrafficAndAppCache()
    testV061PreviewAutoPause()
    testV062SystemPulseEdgeOrientation()
    try testV063BinarySnapshotFSEventsAndDirCache()
    try testV064ScreenshotAutoPasteboardAndRestore()
    try testV065PerformanceCompactIndexHeaderAndFormatters()
    print("ALL LUMAKEY CHECKS PASSED")
} catch {
    fputs("UNEXPECTED ERROR: \(error)\n", stderr)
    exit(1)
}
