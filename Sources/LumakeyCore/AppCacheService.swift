import Foundation

public enum AppCacheBucketKind: String, CaseIterable, Identifiable, Sendable {
    case clipboardImages, screenshotsAndPins, visionCutouts, cinemaRemux, diskIndexSnapshot, inMemoryIndexes, appSupportConfig
    public var id: String { rawValue }
    public var isProtected: Bool { self == .appSupportConfig }

    public var title: String {
        switch self {
        case .clipboardImages: "剪贴板图片与富媒体缓存"
        case .screenshotsAndPins: "选区截图与贴图临时文件"
        case .visionCutouts: "Vision 主体抠图缓存"
        case .cinemaRemux: "影院容器转封装临时缓存"
        case .diskIndexSnapshot: "全盘文件索引二进制快照"
        case .inMemoryIndexes: "内存全盘索引与预览缓存"
        case .appSupportConfig: "应用配置与扩展插件数据"
        }
    }

    public var subtitle: String {
        switch self {
        case .clipboardImages: "自动保留已收藏/置顶的剪贴板文件，其余可安全释放"
        case .screenshotsAndPins: "含截图、OCR 与钉屏临时 PNG（跳过仍在置顶引用的文件）"
        case .visionCutouts: "离线主体分割生成的透明 PNG 缓存"
        case .cinemaRemux: "MKV/AVI 等封装无损重封 MP4 临时缓存"
        case .diskIndexSnapshot: "Everything 二进制快照 (.lmkyidx)，支持 mmap 秒开启动"
        case .inMemoryIndexes: "Everything 内存节点、目录缓存与工作台缩略图计数"
        case .appSupportConfig: "存放 Mos 规则、系统脉搏配置与自定义扩展（受保护）"
        }
    }
}

public struct AppCacheBucketReport: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: AppCacheBucketKind
    public let title: String
    public let subtitle: String
    public let locationURL: URL?
    public let fileCount: Int
    public let sizeBytes: Int64
    public let isProtected: Bool

    public init(
        id: String,
        kind: AppCacheBucketKind,
        title: String,
        subtitle: String,
        locationURL: URL?,
        fileCount: Int,
        sizeBytes: Int64,
        isProtected: Bool
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.locationURL = locationURL
        self.fileCount = fileCount
        self.sizeBytes = sizeBytes
        self.isProtected = isProtected
    }
}

public struct AppCacheOverview: Sendable {
    public let buckets: [AppCacheBucketReport]
    public let purgeableBytes: Int64
    public let protectedBytes: Int64
    public let residentMemoryMB: Double

    public init(
        buckets: [AppCacheBucketReport],
        purgeableBytes: Int64,
        protectedBytes: Int64,
        residentMemoryMB: Double
    ) {
        self.buckets = buckets
        self.purgeableBytes = purgeableBytes
        self.protectedBytes = protectedBytes
        self.residentMemoryMB = residentMemoryMB
    }
}

public enum AppCacheService {
    public static func defaultAppSupportRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Lumakey", isDirectory: true)
    }

    private static func resolveIndexCacheDirectory(tempRoot: URL, indexCacheRoot: URL?) -> URL {
        if let indexCacheRoot { return indexCacheRoot }
        if tempRoot == FileManager.default.temporaryDirectory {
            return EverythingSnapshotStore.defaultCacheDirectory()
        }
        return tempRoot.appendingPathComponent("lumakey-index", isDirectory: true)
    }

    public static func inspectAll(
        tempRoot: URL = FileManager.default.temporaryDirectory,
        appSupportRoot: URL? = nil,
        indexCacheRoot: URL? = nil,
        inMemoryEstimatedBytes: Int64 = 0,
        inMemoryItemCount: Int = 0
    ) -> AppCacheOverview {
        let supportDir = appSupportRoot ?? defaultAppSupportRoot()
        let indexDir = resolveIndexCacheDirectory(tempRoot: tempRoot, indexCacheRoot: indexCacheRoot)
        let reports: [AppCacheBucketReport] = AppCacheBucketKind.allCases.map { kind in
            switch kind {
            case .clipboardImages:
                let dir = tempRoot.appendingPathComponent("lumakey-clipboard", isDirectory: true)
                let stats = measureDirectory(dir)
                return makeReport(kind, url: dir, count: stats.count, bytes: stats.bytes)
            case .screenshotsAndPins:
                let files = screenshotTempFiles(in: tempRoot)
                let total = files.reduce(Int64(0)) { $0 + fileSize($1) }
                return makeReport(kind, url: tempRoot, count: files.count, bytes: total)
            case .visionCutouts:
                let dir = tempRoot.appendingPathComponent("lumakey-cutouts", isDirectory: true)
                let stats = measureDirectory(dir)
                return makeReport(kind, url: dir, count: stats.count, bytes: stats.bytes)
            case .cinemaRemux:
                let dir = tempRoot.appendingPathComponent("lumakey-cinema", isDirectory: true)
                let stats = measureDirectory(dir)
                return makeReport(kind, url: dir, count: stats.count, bytes: stats.bytes)
            case .diskIndexSnapshot:
                let stats = measureDirectory(indexDir)
                return makeReport(kind, url: indexDir, count: stats.count, bytes: stats.bytes)
            case .inMemoryIndexes:
                return makeReport(kind, url: nil, count: inMemoryItemCount, bytes: inMemoryEstimatedBytes)
            case .appSupportConfig:
                let stats = measureDirectory(supportDir)
                return makeReport(kind, url: supportDir, count: stats.count, bytes: stats.bytes)
            }
        }
        let purgeable = reports.filter { !$0.isProtected && $0.kind != .inMemoryIndexes }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let protected = reports.filter(\.isProtected).reduce(Int64(0)) { $0 + $1.sizeBytes }
        return AppCacheOverview(
            buckets: reports,
            purgeableBytes: purgeable,
            protectedBytes: protected,
            residentMemoryMB: MemoryStats.currentPhysicalFootprintMB()
        )
    }

    @discardableResult
    public static func clearBucket(
        _ kind: AppCacheBucketKind,
        protectedURLs: Set<URL> = [],
        tempRoot: URL = FileManager.default.temporaryDirectory,
        indexCacheRoot: URL? = nil,
        onClearMemory: (() -> Void)? = nil
    ) -> Int64 {
        guard !kind.isProtected else { return 0 }
        let protectedPaths = Set(protectedURLs.map { $0.standardizedFileURL.path })
        switch kind {
        case .clipboardImages:
            return removeFiles(in: tempRoot.appendingPathComponent("lumakey-clipboard", isDirectory: true), excluding: protectedPaths)
        case .screenshotsAndPins:
            var freed: Int64 = 0
            for url in screenshotTempFiles(in: tempRoot) where !protectedPaths.contains(url.standardizedFileURL.path) {
                let sz = fileSize(url)
                if (try? FileManager.default.removeItem(at: url)) != nil { freed += sz }
            }
            return freed
        case .visionCutouts:
            return removeFiles(in: tempRoot.appendingPathComponent("lumakey-cutouts", isDirectory: true), excluding: protectedPaths)
        case .cinemaRemux:
            return removeFiles(in: tempRoot.appendingPathComponent("lumakey-cinema", isDirectory: true), excluding: protectedPaths)
        case .diskIndexSnapshot:
            let indexDir = resolveIndexCacheDirectory(tempRoot: tempRoot, indexCacheRoot: indexCacheRoot)
            return EverythingSnapshotStore.removeAllSnapshots(cacheDirectory: indexDir)
        case .inMemoryIndexes:
            onClearMemory?()
            return 0
        case .appSupportConfig:
            return 0
        }
    }

    @discardableResult
    public static func clearAllPurgeable(
        protectedURLs: Set<URL> = [],
        tempRoot: URL = FileManager.default.temporaryDirectory,
        indexCacheRoot: URL? = nil,
        onClearMemory: (() -> Void)? = nil
    ) -> Int64 {
        var total: Int64 = 0
        for kind in AppCacheBucketKind.allCases where !kind.isProtected {
            total += clearBucket(
                kind,
                protectedURLs: protectedURLs,
                tempRoot: tempRoot,
                indexCacheRoot: indexCacheRoot,
                onClearMemory: onClearMemory
            )
        }
        return total
    }

    private static func makeReport(_ kind: AppCacheBucketKind, url: URL?, count: Int, bytes: Int64) -> AppCacheBucketReport {
        AppCacheBucketReport(
            id: kind.rawValue, kind: kind, title: kind.title, subtitle: kind.subtitle,
            locationURL: url, fileCount: count, sizeBytes: bytes, isProtected: kind.isProtected
        )
    }

    private static func screenshotTempFiles(in tempRoot: URL) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: [.fileSizeKey], options: []) else {
            return []
        }
        return items.filter {
            let name = $0.lastPathComponent
            return name.hasPrefix("lumakey-pin-") || name.hasPrefix("lumakey-capture-") || name.hasPrefix("lumakey-ocr-")
        }
    }

    private static func measureDirectory(_ dir: URL) -> (count: Int, bytes: Int64) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) else {
            return (0, 0)
        }
        var count = 0
        var total: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if vals?.isRegularFile == true {
                count += 1
                total += Int64(vals?.fileSize ?? 0)
            }
        }
        return (count, total)
    }

    private static func removeFiles(in dir: URL, excluding protectedPaths: Set<String>) -> Int64 {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: []) else {
            return 0
        }
        var freed: Int64 = 0
        for item in items where !protectedPaths.contains(item.standardizedFileURL.path) {
            let sz = fileSize(item)
            if (try? fm.removeItem(at: item)) != nil { freed += sz }
        }
        return freed
    }

    private static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
