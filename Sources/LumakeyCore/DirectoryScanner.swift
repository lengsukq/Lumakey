import CryptoKit
import Darwin
import Foundation

public enum DirectoryScanner {
    public static func directoryModificationDate(at directoryURL: URL) -> Date? {
        var st = stat()
        guard directoryURL.path.withCString({ stat($0, &st) == 0 }) else { return nil }
        let seconds = TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1_000_000_000
        return Date(timeIntervalSince1970: seconds)
    }

    public static func scanDirectory(
        at directoryURL: URL,
        includeHidden: Bool,
        skipExtendedTags: Bool = false
    ) throws -> [FileEntry] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw LumakeyError.directoryNotFound(directoryURL)
        }
        var keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isPackageKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey
        ]
        if !skipExtendedTags {
            keys.append(.tagNamesKey)
        }
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: keys,
                options: includeHidden ? [] : [.skipsHiddenFiles]
            )
        } catch {
            throw LumakeyError.directoryUnreadable(directoryURL, error.localizedDescription)
        }
        let keySet = Set(keys)
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: keySet)
            let isDirectory = values?.isDirectory ?? false
            let isPackage = values?.isPackage ?? false
            let isHidden = values?.isHidden ?? url.lastPathComponent.hasPrefix(".")
            let size = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate ?? .distantPast
            let created = values?.creationDate ?? modified
            let ext = url.pathExtension.lowercased()
            let mediaKind = MediaClassifier.classify(url: url, isDirectory: isDirectory && !isPackage)
            return FileEntry(
                url: url,
                name: url.lastPathComponent,
                isDirectory: isDirectory,
                isPackage: isPackage,
                isHidden: isHidden,
                sizeBytes: size,
                modifiedAt: modified,
                createdAt: created,
                extensionLowercased: ext,
                mediaKind: mediaKind,
                tags: skipExtendedTags ? [] : (values?.tagNames ?? [])
            )
        }
    }

    public static func sortEntries(
        _ entries: [FileEntry],
        by field: SortField,
        order: LumakeySortOrder,
        foldersFirst: Bool = true
    ) -> [FileEntry] {
        entries.sorted { lhs, rhs in
            let lhsIsDir = lhs.isDirectory && !lhs.isPackage
            let rhsIsDir = rhs.isDirectory && !rhs.isPackage
            if foldersFirst && lhsIsDir != rhsIsDir {
                return lhsIsDir && !rhsIsDir
            }
            let cmp: ComparisonResult
            switch field {
            case .name:
                cmp = lhs.name.localizedStandardCompare(rhs.name)
            case .modifiedAt:
                cmp = lhs.modifiedAt.compare(rhs.modifiedAt)
            case .createdAt:
                cmp = lhs.createdAt.compare(rhs.createdAt)
            case .size:
                if lhs.sizeBytes == rhs.sizeBytes {
                    cmp = lhs.name.localizedStandardCompare(rhs.name)
                } else {
                    cmp = lhs.sizeBytes < rhs.sizeBytes ? .orderedAscending : .orderedDescending
                }
            case .kind:
                if lhs.mediaKind == rhs.mediaKind {
                    cmp = lhs.name.localizedStandardCompare(rhs.name)
                } else {
                    cmp = lhs.mediaKind.badgeTitle.localizedStandardCompare(rhs.mediaKind.badgeTitle)
                }
            case .ext:
                if lhs.extensionLowercased == rhs.extensionLowercased {
                    cmp = lhs.name.localizedStandardCompare(rhs.name)
                } else {
                    cmp = lhs.extensionLowercased.localizedStandardCompare(rhs.extensionLowercased)
                }
            }
            if cmp == .orderedSame {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return order == .ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
        }
    }

    public static func computeSHA256(for fileURL: URL, chunkSize: Int = 262_144) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
