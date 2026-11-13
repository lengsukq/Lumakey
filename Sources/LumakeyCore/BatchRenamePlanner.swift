import Foundation

public struct BatchRenameRule: Sendable, Hashable {
    public var findText: String
    public var replaceText: String
    public var prefix: String
    public var suffix: String
    public var useIndexNumbering: Bool
    public var startNumber: Int
    public var zeroPadWidth: Int

    public init(
        findText: String = "",
        replaceText: String = "",
        prefix: String = "",
        suffix: String = "",
        useIndexNumbering: Bool = false,
        startNumber: Int = 1,
        zeroPadWidth: Int = 2
    ) {
        self.findText = findText
        self.replaceText = replaceText
        self.prefix = prefix
        self.suffix = suffix
        self.useIndexNumbering = useIndexNumbering
        self.startNumber = startNumber
        self.zeroPadWidth = zeroPadWidth
    }
}

public struct BatchRenamePreviewItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let sourceURL: URL
    public let originalName: String
    public let proposedName: String
    public let conflictReason: String?

    public var isChanged: Bool { originalName != proposedName }
    public var hasConflict: Bool { conflictReason != nil }
}

public enum BatchRenamePlanner {
    public static func plan(entries: [FileEntry], rule: BatchRenameRule) -> [BatchRenamePreviewItem] {
        var draftNames: [(entry: FileEntry, target: String, invalidReason: String?)] = []
        draftNames.reserveCapacity(entries.count)

        for (offset, entry) in entries.enumerated() {
            let target = buildNewName(for: entry, indexOffset: offset, rule: rule)
            let invalidReason = validateFileName(target)
            draftNames.append((entry, target, invalidReason))
        }

        let sourcePaths = Set(entries.map { $0.url.standardizedFileURL.path })
        var targetCounts: [String: Int] = [:]
        for item in draftNames {
            let targetPath = item.entry.url.deletingLastPathComponent().appendingPathComponent(item.target).standardizedFileURL.path
            targetCounts[targetPath, default: 0] += 1
        }

        return draftNames.map { item in
            let targetURL = item.entry.url.deletingLastPathComponent().appendingPathComponent(item.target)
            let targetPath = targetURL.standardizedFileURL.path
            var conflict = item.invalidReason
            if conflict == nil && (targetCounts[targetPath] ?? 0) > 1 {
                conflict = "批处理内部出现重复名称"
            } else if conflict == nil,
                      item.target != item.entry.name,
                      !sourcePaths.contains(targetPath),
                      FileManager.default.fileExists(atPath: targetPath) {
                conflict = "目标目录中已存在同名文件"
            }
            return BatchRenamePreviewItem(
                id: item.entry.id,
                sourceURL: item.entry.url,
                originalName: item.entry.name,
                proposedName: item.target,
                conflictReason: conflict
            )
        }
    }

    public static func apply(_ items: [BatchRenamePreviewItem]) throws {
        let changed = items.filter(\.isChanged)
        if changed.isEmpty { return }
        if let firstDir = changed.first?.sourceURL.deletingLastPathComponent(),
           let vol = VolumeInspector.inspect(url: firstDir),
           vol.isReadOnly {
            throw LumakeyError.readOnlyVolume(vol.name)
        }
        for item in changed {
            if let invalid = validateFileName(item.proposedName) {
                throw LumakeyError.invalidRenameTarget("\(item.proposedName)：\(invalid)")
            }
        }
        if let broken = changed.first(where: \.hasConflict) {
            throw LumakeyError.renameConflict("\(broken.proposedName)：\(broken.conflictReason ?? "命名冲突")")
        }
        var staged: [(tempURL: URL, finalURL: URL)] = []
        for item in changed {
            let dir = item.sourceURL.deletingLastPathComponent()
            let tempURL = dir.appendingPathComponent(".lumakey-rename-\(UUID().uuidString)")
            let finalURL = dir.appendingPathComponent(item.proposedName)
            try FileManager.default.moveItem(at: item.sourceURL, to: tempURL)
            staged.append((tempURL, finalURL))
        }
        for pair in staged {
            try FileManager.default.moveItem(at: pair.tempURL, to: pair.finalURL)
        }
    }

    private static func buildNewName(for entry: FileEntry, indexOffset: Int, rule: BatchRenameRule) -> String {
        let ext = entry.isDirectory && !entry.isPackage ? "" : entry.url.pathExtension
        let stem = ext.isEmpty ? entry.name : entry.url.deletingPathExtension().lastPathComponent
        var updatedStem = stem
        if !rule.findText.isEmpty {
            updatedStem = updatedStem.replacingOccurrences(of: rule.findText, with: rule.replaceText)
        }
        updatedStem = rule.prefix + updatedStem + rule.suffix
        if rule.useIndexNumbering {
            let number = rule.startNumber + indexOffset
            let format = "%0\(max(1, min(6, rule.zeroPadWidth)))d"
            updatedStem += "_\(String(format: format, number))"
        }
        return ext.isEmpty ? updatedStem : "\(updatedStem).\(ext)"
    }

    private static func validateFileName(_ name: String) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "名称不能为空" }
        if name == "." || name == ".." { return "名称不能为 . 或 .." }
        if name.contains("/") || name.contains(":") { return "名称不能包含 / 或 :" }
        return nil
    }
}
