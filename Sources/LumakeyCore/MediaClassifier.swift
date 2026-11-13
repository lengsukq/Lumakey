import CoreGraphics
import Foundation
import ImageIO

public enum PreviewMediaKind: String, Sendable, Hashable {
    case folder
    case image
    case video
    case audio
    case pdf
    case markdown
    case text
    case archive
    case other

    public var badgeTitle: String {
        switch self {
        case .folder: "文件夹"
        case .image: "图像"
        case .video: "视频"
        case .audio: "音频"
        case .pdf: "PDF 文档"
        case .markdown: "Markdown"
        case .text: "文本 / 代码"
        case .archive: "压缩归档"
        case .other: "常规文件"
        }
    }

    public var symbolName: String {
        switch self {
        case .folder: "folder.fill"
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .pdf: "doc.richtext"
        case .markdown: "text.document.fill"
        case .text: "doc.plaintext"
        case .archive: "doc.zipper"
        case .other: "doc"
        }
    }
}

public enum MediaClassifier {
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "heic", "heif", "gif", "tiff", "tif", "bmp", "ico", "raw", "dng"
    ]
    public static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "ts", "flv", "wmv"
    ]
    public static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "flac", "aiff", "ogg"
    ]
    public static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdx"
    ]
    public static let textExtensions: Set<String> = [
        "txt", "swift", "py", "js", "ts", "tsx", "json", "yaml", "yml",
        "toml", "xml", "html", "css", "sh", "zsh", "c", "h", "cpp", "rs", "go", "log", "csv", "ini", "conf"
    ]
    public static let archiveExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg"
    ]

    public static func classify(url: URL, isDirectory: Bool) -> PreviewMediaKind {
        classifyExtension(url.pathExtension.lowercased(), isDirectory: isDirectory)
    }

    public static func classifyExtension(_ ext: String, isDirectory: Bool) -> PreviewMediaKind {
        if isDirectory { return .folder }
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if ext == "pdf" { return .pdf }
        if markdownExtensions.contains(ext) { return .markdown }
        if textExtensions.contains(ext) { return .text }
        if archiveExtensions.contains(ext) { return .archive }
        return .other
    }

    public static func readImageDimensions(at url: URL) -> CGSize? {
        let sourceOpts: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOpts),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOpts) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat
        else { return nil }
        return CGSize(width: width, height: height)
    }

    public static func makeThumbnail(at url: URL, maxPixelSize: Int = 720) -> CGImage? {
        autoreleasepool {
            let sourceOpts: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOpts) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceShouldCache: false,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
    }

    public static func loadTextPreview(at url: URL, maxBytes: Int = 16_384) -> (text: String, isTruncated: Bool) {
        loadDocumentText(at: url, maxBytes: maxBytes)
    }

    public static func loadDocumentText(at url: URL, maxBytes: Int = 262_144) -> (text: String, isTruncated: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ("无法读取文本内容。", false)
        }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: maxBytes + 1)) ?? Data()
        let truncated = data.count > maxBytes
        let bounded = truncated ? data.prefix(maxBytes) : data[...]
        if let decoded = String(data: bounded, encoding: .utf8) {
            return (decoded, truncated)
        }
        return ("文件不是有效的 UTF-8 文本编码（可能是二进制文件）。", false)
    }

    public static func siblingMediaURLs(around url: URL, matching kinds: Set<PreviewMediaKind>) -> [URL] {
        let dir = url.deletingLastPathComponent()
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [url]
        }
        let filtered = items.filter { candidate in
            let isDir = (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return kinds.contains(classify(url: candidate, isDirectory: isDir))
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return filtered.isEmpty ? [url] : filtered
    }
}
