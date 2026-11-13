import Darwin
import Foundation

public enum VolumeFormatKind: String, Sendable, Hashable {
    case apfs
    case ntfsReadOnly
    case ntfsFuseWritable
    case exFAT
    case smb
    case other

    public var badgeText: String {
        switch self {
        case .apfs: "APFS"
        case .ntfsReadOnly: "NTFS · 只读"
        case .ntfsFuseWritable: "NTFS/FUSE · 读写"
        case .exFAT: "exFAT"
        case .smb: "SMB"
        case .other: "存储卷"
        }
    }
}

public struct VolumeSummary: Sendable, Hashable {
    public let name: String
    public let mountPath: String
    public let fileSystemType: String
    public let formatKind: VolumeFormatKind
    public let isReadOnly: Bool
    public let isExternal: Bool
    public let totalBytes: Int64?
    public let availableBytes: Int64?

    public init(
        name: String,
        mountPath: String,
        fileSystemType: String,
        formatKind: VolumeFormatKind,
        isReadOnly: Bool,
        isExternal: Bool,
        totalBytes: Int64?,
        availableBytes: Int64?
    ) {
        self.name = name
        self.mountPath = mountPath
        self.fileSystemType = fileSystemType
        self.formatKind = formatKind
        self.isReadOnly = isReadOnly
        self.isExternal = isExternal
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }

    public var capacityText: String {
        guard let totalBytes, let availableBytes else { return "容量未知" }
        let avail = FastFormatters.formatFileBytes(availableBytes)
        let total = FastFormatters.formatFileBytes(totalBytes)
        return "可用 \(avail) / 共 \(total)"
    }
}

public struct HostToolingStatus: Sendable, Hashable {
    public let ntfs3gPath: String?
    public let mountNtfsPath: String?
    public let ffmpegPath: String?
    public let ffprobePath: String?

    public init(
        ntfs3gPath: String? = nil,
        mountNtfsPath: String? = nil,
        ffmpegPath: String? = nil,
        ffprobePath: String? = nil
    ) {
        self.ntfs3gPath = ntfs3gPath
        self.mountNtfsPath = mountNtfsPath
        self.ffmpegPath = ffmpegPath
        self.ffprobePath = ffprobePath
    }

    public static func detect() -> HostToolingStatus {
        HostToolingStatus(
            ntfs3gPath: firstExecutable(["/opt/homebrew/bin/ntfs-3g", "/usr/local/bin/ntfs-3g"]),
            mountNtfsPath: firstExecutable(["/opt/homebrew/sbin/mount_ntfs", "/usr/local/sbin/mount_ntfs"]),
            ffmpegPath: firstExecutable(["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]),
            ffprobePath: firstExecutable(["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"])
        )
    }

    private static func firstExecutable(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

public enum VolumeInspector {
    public static func inspect(url: URL) -> VolumeSummary? {
        var fsStat = statfs()
        guard url.path.withCString({ statfs($0, &fsStat) }) == 0 else { return nil }
        let fsType = withUnsafePointer(to: &fsStat.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
        }
        let mountPath = withUnsafePointer(to: &fsStat.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        let mountURL = URL(fileURLWithPath: mountPath)
        let values = try? mountURL.resourceValues(forKeys: [
            .volumeNameKey, .volumeIsReadOnlyKey, .volumeIsInternalKey,
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ])
        let isReadOnly = (values?.volumeIsReadOnly ?? false) || ((Int32(fsStat.f_flags) & MNT_RDONLY) != 0)
        let isInternal = values?.volumeIsInternal ?? (mountPath == "/")
        let name = values?.volumeName ?? (mountURL.lastPathComponent.isEmpty ? "Macintosh HD" : mountURL.lastPathComponent)
        return VolumeSummary(
            name: name,
            mountPath: mountPath,
            fileSystemType: fsType,
            formatKind: classifyFormat(fsType: fsType, isReadOnly: isReadOnly),
            isReadOnly: isReadOnly,
            isExternal: !isInternal,
            totalBytes: values?.volumeTotalCapacity.map(Int64.init),
            availableBytes: values?.volumeAvailableCapacityForImportantUsage
        )
    }

    public static func mountedVolumes() -> [VolumeSummary] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsBrowsableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return []
        }
        return urls.compactMap(inspect(url:)).filter { vol in
            vol.mountPath != "/Volumes/Recovery"
                && !vol.mountPath.hasPrefix("/System/Volumes/")
                && vol.mountPath != "/private/var/vm"
        }
    }

    public static func externalVolumes() -> [VolumeSummary] {
        mountedVolumes().filter { $0.mountPath != "/" }
    }

    public static func isSlowOrRemoteVolume(_ vol: VolumeSummary) -> Bool {
        let lower = vol.fileSystemType.lowercased()
        return vol.formatKind == .smb || lower.contains("fuse") || lower.contains("ntfs")
    }

    public static func classifyFormat(fsType: String, isReadOnly: Bool) -> VolumeFormatKind {
        let lower = fsType.lowercased()
        if lower == "apfs" { return .apfs }
        if lower == "ntfs" { return isReadOnly ? .ntfsReadOnly : .ntfsFuseWritable }
        if lower.contains("fuse") || lower.contains("ntfs-3g") {
            return isReadOnly ? .ntfsReadOnly : .ntfsFuseWritable
        }
        if lower == "exfat" { return .exFAT }
        if lower.contains("smb") { return .smb }
        return .other
    }
}
