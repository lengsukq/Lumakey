import AppKit
import CoreGraphics
import Foundation

public enum ClipboardCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case text = "文本"
    case image = "图片"
    case file = "文件"
    case pinned = "收藏"

    public var id: String { rawValue }
}

public enum ClipboardPayloadKind: Sendable, Hashable {
    case text
    case colorHex(String)
    case image(URL, CGSize)
    case file(URL)

    public var badgeTitle: String {
        switch self {
        case .text: "文本"
        case .colorHex: "色值"
        case .image: "图片"
        case .file: "文件"
        }
    }
}

public struct ClipboardEntry: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let textValue: String?
    public let fileURL: URL?
    public let capturedAt: Date
    public var isPinned: Bool
    public let payloadKind: ClipboardPayloadKind

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        textValue: String? = nil,
        fileURL: URL? = nil,
        capturedAt: Date = Date(),
        isPinned: Bool = false,
        payloadKind: ClipboardPayloadKind
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.textValue = textValue
        self.fileURL = fileURL
        self.capturedAt = capturedAt
        self.isPinned = isPinned
        self.payloadKind = payloadKind
    }
}

public enum ClipboardService {
    public static let concealedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "com.agilebits.onepassword"
    ]

    @MainActor
    public static func captureCurrent(from pasteboard: NSPasteboard = .general) -> ClipboardEntry? {
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: concealedTypes) else { return nil }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first {
            return ClipboardEntry(
                title: first.lastPathComponent,
                subtitle: first.deletingLastPathComponent().path,
                fileURL: first,
                payloadKind: .file(first)
            )
        }

        if let str = pasteboard.string(forType: .string) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
            if let hex = parseHexColor(trimmed) {
                return ClipboardEntry(title: hex, subtitle: "颜色 HEX · \(trimmed.count) 字符", textValue: str, payloadKind: .colorHex(hex))
            }
            return ClipboardEntry(
                title: String(firstLine.prefix(90)),
                subtitle: "文本 · \(trimmed.count) 字",
                textValue: str,
                payloadKind: .text
            )
        }

        if let rawPNG = pasteboard.data(forType: .png), !rawPNG.isEmpty {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-clipboard", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("clip-\(UUID().uuidString).png")
            if (try? rawPNG.write(to: url)) != nil {
                let dims = MediaClassifier.readImageDimensions(at: url) ?? .zero
                return ClipboardEntry(
                    title: "剪贴板图片 \(Int(dims.width))×\(Int(dims.height))",
                    subtitle: url.lastPathComponent,
                    fileURL: url,
                    payloadKind: .image(url, dims)
                )
            }
        }

        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-clipboard", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("clip-\(UUID().uuidString).png")
            if (try? png.write(to: url)) != nil {
                let dims = MediaClassifier.readImageDimensions(at: url) ?? image.size
                return ClipboardEntry(
                    title: "剪贴板图片 \(Int(dims.width))×\(Int(dims.height))",
                    subtitle: url.lastPathComponent,
                    fileURL: url,
                    payloadKind: .image(url, dims)
                )
            }
        }
        return nil
    }

    public static func insert(_ entry: ClipboardEntry, into list: [ClipboardEntry], maxUnpinned: Int = 80) -> [ClipboardEntry] {
        var next = list
        var preservedPin = entry.isPinned
        var removed: [ClipboardEntry] = []
        next.removeAll { existing in
            let match = (entry.textValue != nil && existing.textValue == entry.textValue)
                || (entry.fileURL != nil && existing.fileURL?.path == entry.fileURL?.path)
            if match && existing.isPinned { preservedPin = true }
            if match && existing.fileURL?.path != entry.fileURL?.path {
                removed.append(existing)
            }
            return match
        }
        var updated = entry
        updated.isPinned = preservedPin
        next.insert(updated, at: 0)

        var unpinnedSeen = 0
        var kept: [ClipboardEntry] = []
        kept.reserveCapacity(next.count)
        for item in next {
            if item.isPinned {
                kept.append(item)
            } else {
                unpinnedSeen += 1
                if unpinnedSeen <= maxUnpinned {
                    kept.append(item)
                } else {
                    removed.append(item)
                }
            }
        }
        removeTempFiles(for: removed)
        return kept
    }

    public static func removeTempFiles(for entries: [ClipboardEntry]) {
        for item in entries {
            if case .image(let url, _) = item.payloadKind,
               url.path.contains("lumakey-clipboard") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    public static func filter(_ list: [ClipboardEntry], query: String, category: ClipboardCategory) -> [ClipboardEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return list.filter { item in
            let catOK: Bool
            switch category {
            case .all: catOK = true
            case .text: catOK = item.textValue != nil
            case .image:
                if case .image = item.payloadKind { catOK = true } else { catOK = false }
            case .file:
                if case .file = item.payloadKind { catOK = true } else { catOK = false }
            case .pinned: catOK = item.isPinned
            }
            guard catOK else { return false }
            guard !needle.isEmpty else { return true }
            return item.title.localizedCaseInsensitiveContains(needle)
                || item.subtitle.localizedCaseInsensitiveContains(needle)
                || (item.textValue?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    @MainActor
    public static func copyToPasteboard(_ entry: ClipboardEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch entry.payloadKind {
        case .text, .colorHex:
            if let text = entry.textValue { pb.setString(text, forType: .string) }
        case .file(let url):
            pb.writeObjects([url as NSURL])
        case .image(let url, _):
            _ = ScreenshotCompositor.copyImageFileToPasteboard(at: url, to: pb)
        }
    }

    public static func parseHexColor(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 7, s.hasPrefix("#"),
              s.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return s.uppercased()
    }
}
