import Foundation

public enum WorkspaceClipboardMode: String, Sendable, Hashable {
    case copy
    case cutMove
}

public struct WorkspaceClipboardState: Sendable, Hashable {
    public var urls: [URL]
    public var mode: WorkspaceClipboardMode

    public init(urls: [URL], mode: WorkspaceClipboardMode) {
        self.urls = WorkspaceFileOperations.deduplicateURLs(urls)
        self.mode = mode
    }

    public var isEmpty: Bool { urls.isEmpty }

    public func contains(_ url: URL) -> Bool {
        let target = url.standardizedFileURL.path
        return urls.contains { $0.standardizedFileURL.path == target }
    }
}

public enum WorkspaceFileOperations {
    public static func checkWritableDirectory(
        _ dirURL: URL,
        inspectVolume: (URL) -> VolumeSummary? = VolumeInspector.inspect
    ) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw LumakeyError.directoryNotFound(dirURL)
        }
        if let vol = inspectVolume(dirURL), vol.formatKind == .ntfsReadOnly || vol.isReadOnly {
            throw LumakeyError.readOnlyVolume(vol.name)
        }
        guard FileManager.default.isWritableFile(atPath: dirURL.path) else {
            throw LumakeyError.fileOperationBlocked(
                title: "目录当前不可写入",
                reason: "当前账户对“\(dirURL.lastPathComponent)”没有写入权限。",
                nextStep: "请检查文件夹读写权限，或选择其他可写目录。"
            )
        }
    }

    public static func validateItemName(_ rawName: String) throws -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw LumakeyError.invalidRenameTarget("名称不能为空。") }
        if trimmed == "." || trimmed == ".." { throw LumakeyError.invalidRenameTarget("名称不能为“.”或“..”。") }
        if trimmed.contains("/") || trimmed.contains(":") || trimmed.contains("\0") {
            throw LumakeyError.invalidRenameTarget("名称不能包含“/”或“:”等保留字符。")
        }
        return trimmed
    }

    @discardableResult
    public static func createFolder(
        named: String, in parentDir: URL, inspectVolume: (URL) -> VolumeSummary? = VolumeInspector.inspect
    ) throws -> URL {
        try checkWritableDirectory(parentDir, inspectVolume: inspectVolume)
        let cleanName = try validateItemName(named)
        let targetURL = parentDir.appendingPathComponent(cleanName, isDirectory: true)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            throw LumakeyError.renameConflict("当前目录中已存在同名项目“\(cleanName)”。")
        }
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: false)
        return targetURL
    }

    @discardableResult
    public static func renameItem(
        at url: URL, to newName: String, inspectVolume: (URL) -> VolumeSummary? = VolumeInspector.inspect
    ) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { throw LumakeyError.directoryNotFound(url) }
        let parentDir = url.deletingLastPathComponent()
        try checkWritableDirectory(parentDir, inspectVolume: inspectVolume)
        let cleanName = try validateItemName(newName)
        if cleanName == url.lastPathComponent { return url }

        let targetURL = parentDir.appendingPathComponent(cleanName)
        if fm.fileExists(atPath: targetURL.path) {
            if isSameFileResource(url, targetURL) {
                let tempURL = parentDir.appendingPathComponent(".lumakey-rename-\(UUID().uuidString)")
                try fm.moveItem(at: url, to: tempURL)
                try fm.moveItem(at: tempURL, to: targetURL)
                return targetURL
            }
            throw LumakeyError.renameConflict("同目录下已存在“\(cleanName)”，已拦截覆盖。")
        }
        try fm.moveItem(at: url, to: targetURL)
        return targetURL
    }

    @discardableResult
    public static func copyItems(
        _ urls: [URL], to destinationDir: URL, inspectVolume: (URL) -> VolumeSummary? = VolumeInspector.inspect
    ) throws -> [URL] {
        let uniqueSources = deduplicateURLs(urls)
        if uniqueSources.isEmpty { return [] }
        try checkWritableDirectory(destinationDir, inspectVolume: inspectVolume)
        let fm = FileManager.default
        for src in uniqueSources {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: src.path, isDirectory: &isDir) else { throw LumakeyError.directoryNotFound(src) }
            if isDir.boolValue && isSameOrDescendant(candidate: destinationDir, of: src) {
                throw LumakeyError.fileOperationBlocked(
                    title: "无法复制文件夹",
                    reason: "不能将文件夹“\(src.lastPathComponent)”复制到其自身或其子目录中。",
                    nextStep: "请选择其他目标目录。"
                )
            }
        }
        return try uniqueSources.map { src in
            let dst = uniqueCopyDestinationURL(for: src, in: destinationDir)
            try fm.copyItem(at: src, to: dst)
            return dst
        }
    }

    @discardableResult
    public static func moveItems(
        _ urls: [URL], to destinationDir: URL, inspectVolume: (URL) -> VolumeSummary? = VolumeInspector.inspect
    ) throws -> [URL] {
        let uniqueSources = deduplicateURLs(urls)
        if uniqueSources.isEmpty { return [] }
        try checkWritableDirectory(destinationDir, inspectVolume: inspectVolume)

        let fm = FileManager.default
        let dstCanonical = canonicalPath(destinationDir)
        var plannedTargets = Set<String>()
        var plan: [(src: URL, dst: URL, isNoOp: Bool)] = []

        for src in uniqueSources {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: src.path, isDirectory: &isDir) else { throw LumakeyError.directoryNotFound(src) }
            try checkWritableDirectory(src.deletingLastPathComponent(), inspectVolume: inspectVolume)
            if isDir.boolValue && isSameOrDescendant(candidate: destinationDir, of: src) {
                throw LumakeyError.fileOperationBlocked(
                    title: "无法移动文件夹",
                    reason: "不能将文件夹“\(src.lastPathComponent)”移入其自身或其子目录中。",
                    nextStep: "请选择该文件夹以外的目标目录。"
                )
            }
            if canonicalPath(src.deletingLastPathComponent()) == dstCanonical {
                plan.append((src, src, true))
                continue
            }
            let targetURL = destinationDir.appendingPathComponent(src.lastPathComponent)
            let targetKey = targetURL.standardizedFileURL.path.lowercased()
            if !plannedTargets.insert(targetKey).inserted || fm.fileExists(atPath: targetURL.path) {
                throw LumakeyError.renameConflict("目标目录已存在同名项目“\(src.lastPathComponent)”，已取消移动以保护原文件。")
            }
            plan.append((src, targetURL, false))
        }

        return try plan.map { step in
            if !step.isNoOp { try fm.moveItem(at: step.src, to: step.dst) }
            return step.dst
        }
    }

    @discardableResult
    public static func trashItems(
        _ urls: [URL], inspectVolume: (URL) -> VolumeSummary? = VolumeInspector.inspect
    ) throws -> [URL] {
        let uniqueSources = deduplicateURLs(urls)
        if uniqueSources.isEmpty { return [] }
        let fm = FileManager.default
        for src in uniqueSources {
            guard fm.fileExists(atPath: src.path) else { throw LumakeyError.directoryNotFound(src) }
            try checkWritableDirectory(src.deletingLastPathComponent(), inspectVolume: inspectVolume)
        }
        return try uniqueSources.map { src in
            var resulting: NSURL?
            try fm.trashItem(at: src, resultingItemURL: &resulting)
            return (resulting as URL?) ?? src
        }
    }

    public static func uniqueCopyDestinationURL(for sourceURL: URL, in destinationDir: URL) -> URL {
        let fm = FileManager.default
        let originalName = sourceURL.lastPathComponent
        let direct = destinationDir.appendingPathComponent(originalName)
        if !fm.fileExists(atPath: direct.path) { return direct }

        var isDir: ObjCBool = false
        _ = fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir)
        let isPkg = (try? sourceURL.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
        let plainStem = (isDir.boolValue && !isPkg) || (originalName.hasPrefix(".") && !originalName.dropFirst().contains("."))
        let ext = plainStem ? "" : sourceURL.pathExtension
        let stem = ext.isEmpty ? originalName : sourceURL.deletingPathExtension().lastPathComponent

        for attempt in 1...10_000 {
            let suffix = attempt == 1 ? " 副本" : " 副本 \(attempt)"
            let candidate = destinationDir.appendingPathComponent(ext.isEmpty ? "\(stem)\(suffix)" : "\(stem)\(suffix).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return destinationDir.appendingPathComponent("\(stem) 副本-\(UUID().uuidString.prefix(6))\(ext.isEmpty ? "" : ".\(ext)")")
    }

    public static func isSameOrDescendant(candidate: URL, of ancestor: URL) -> Bool {
        let candPath = canonicalPath(candidate)
        let ancPath = canonicalPath(ancestor)
        return candPath == ancPath || candPath.hasPrefix(ancPath + "/")
    }

    public static func deduplicateURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func isSameFileResource(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let idA = try? lhs.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let idB = try? rhs.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else { return false }
        return idA.isEqual(idB)
    }
}
