import Foundation

public struct SnippetItem: Identifiable, Codable, Sendable, Hashable, Equatable {
    public let id: UUID
    public var title: String
    public var keyword: String
    public var content: String
    public var category: String
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        keyword: String,
        content: String,
        category: String = "通用",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.keyword = keyword
        self.content = content
        self.category = category
        self.updatedAt = updatedAt
    }
}

public struct SnippetMatch: Identifiable, Sendable, Hashable, Equatable {
    public var id: UUID { snippet.id }
    public let snippet: SnippetItem
    public let expandedText: String
    public let score: Int

    public init(snippet: SnippetItem, expandedText: String, score: Int) {
        self.snippet = snippet
        self.expandedText = expandedText
        self.score = score
    }
}

public final class SnippetStore: @unchecked Sendable {
    public static let shared = SnippetStore()

    public let fileURL: URL
    private let lock = NSLock()
    private var cached: [SnippetItem]?

    public static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Lumakey", isDirectory: true)
            .appendingPathComponent("snippets.json")
    }

    public static func defaultSnippets() -> [SnippetItem] {
        let ref = Date(timeIntervalSince1970: 1_730_000_000)
        return [
            SnippetItem(title: "当前日期", keyword: ";date", content: "{{date}}", category: "时间", updatedAt: ref),
            SnippetItem(title: "当前日期时间", keyword: ";time", content: "{{datetime}}", category: "时间", updatedAt: ref),
            SnippetItem(title: "Bash 严格脚本头", keyword: ";sh", content: "#!/usr/bin/env bash\nset -euo pipefail\n\n", category: "开发", updatedAt: ref),
            SnippetItem(title: "动态随机 UUID", keyword: ";uuid", content: "{{uuid}}", category: "开发", updatedAt: ref),
            SnippetItem(title: "引用剪贴板代码块", keyword: ";clip", content: "```\n{{clipboard}}\n```", category: "文档", updatedAt: ref)
        ]
    }

    public init(fileURL: URL = SnippetStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func allSnippets() -> [SnippetItem] {
        lock.withLock {
            if let cached { return cached }
            let loaded = loadFromDiskUnlocked()
            cached = loaded
            return loaded
        }
    }

    @discardableResult
    public func upsert(_ item: SnippetItem) throws -> SnippetItem {
        try lock.withLock {
            var list = cached ?? loadFromDiskUnlocked()
            var clean = item
            clean.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            clean.keyword = item.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            clean.updatedAt = Date()
            if clean.title.isEmpty { clean.title = clean.keyword.isEmpty ? "未命名短语" : clean.keyword }
            if let idx = list.firstIndex(where: { $0.id == clean.id }) {
                list[idx] = clean
            } else {
                list.insert(clean, at: 0)
            }
            try saveToDiskUnlocked(list)
            cached = list
            return clean
        }
    }

    public func delete(id: UUID) throws {
        try lock.withLock {
            var list = cached ?? loadFromDiskUnlocked()
            list.removeAll { $0.id == id }
            try saveToDiskUnlocked(list)
            cached = list
        }
    }

    public func resetToDefaults() throws -> [SnippetItem] {
        try lock.withLock {
            let defaults = Self.defaultSnippets()
            try saveToDiskUnlocked(defaults)
            cached = defaults
            return defaults
        }
    }

    public func match(
        query: String,
        clipboardText: String? = nil,
        now: Date = Date()
    ) -> [SnippetMatch] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        let items = allSnippets()
        var matches: [SnippetMatch] = []

        for item in items {
            let kw = item.keyword.lowercased()
            let titleLo = item.title.lowercased()
            var score = 0
            if !kw.isEmpty && kw == needle {
                score = 9_850
            } else if !kw.isEmpty && (kw.hasPrefix(needle) || needle.hasPrefix(kw)) {
                score = 9_600
            } else if titleLo.hasPrefix(needle) {
                score = 8_400
            } else if (!kw.isEmpty && kw.contains(needle)) || titleLo.contains(needle) || item.category.lowercased().contains(needle) {
                score = 7_600
            }
            if score > 0 {
                let expanded = Self.expand(item.content, clipboardText: clipboardText, now: now)
                matches.append(SnippetMatch(snippet: item, expandedText: expanded, score: score))
            }
        }
        return matches.sorted { $0.score != $1.score ? $0.score > $1.score : $0.snippet.keyword < $1.snippet.keyword }
    }

    public static func expand(
        _ template: String,
        clipboardText: String? = nil,
        now: Date = Date()
    ) -> String {
        guard template.contains("{{") else { return template }
        let dateDF = DateFormatter()
        dateDF.locale = Locale(identifier: "en_US_POSIX")
        dateDF.timeZone = .current
        dateDF.dateFormat = "yyyy-MM-dd"

        let timeDF = DateFormatter()
        timeDF.locale = Locale(identifier: "en_US_POSIX")
        timeDF.timeZone = .current
        timeDF.dateFormat = "HH:mm:ss"

        let dateStr = dateDF.string(from: now)
        let timeStr = timeDF.string(from: now)
        var out = template
            .replacingOccurrences(of: "{{date}}", with: dateStr)
            .replacingOccurrences(of: "{{time}}", with: timeStr)
            .replacingOccurrences(of: "{{datetime}}", with: "\(dateStr) \(timeStr)")
            .replacingOccurrences(of: "{{clipboard}}", with: clipboardText ?? "")

        while let range = out.range(of: "{{uuid}}") {
            out.replaceSubrange(range, with: UUID().uuidString.lowercased())
        }
        return out
    }

    private func loadFromDiskUnlocked() -> [SnippetItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SnippetItem].self, from: data)
        else {
            return Self.defaultSnippets()
        }
        return decoded
    }

    private func saveToDiskUnlocked(_ items: [SnippetItem]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(items)
        try data.write(to: fileURL, options: .atomic)
    }
}
