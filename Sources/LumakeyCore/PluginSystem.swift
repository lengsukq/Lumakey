import Foundation

public enum PluginMode: String, Codable, Sendable, Hashable, CaseIterable {
    case script, view
}

public enum PluginConfigFieldType: String, Codable, Sendable, Hashable, CaseIterable {
    case text, secret, boolean, select
}

public struct PluginConfigField: Codable, Sendable, Hashable, Identifiable {
    public var id: String { key }
    public let key: String
    public let label: String
    public let type: PluginConfigFieldType
    public let defaultValue: String?
    public let placeholder: String?
    public let options: [String]?
    public let required: Bool?

    public init(
        key: String, label: String, type: PluginConfigFieldType = .text,
        defaultValue: String? = nil, placeholder: String? = nil,
        options: [String]? = nil, required: Bool? = nil
    ) {
        self.key = key; self.label = label; self.type = type
        self.defaultValue = defaultValue; self.placeholder = placeholder
        self.options = options; self.required = required
    }
}

public struct PluginManifest: Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let mode: PluginMode
    public let keywords: [String]
    public let entry: String
    public let author: String?
    public let icon: String?
    public let hotkey: String?
    public let config: [PluginConfigField]?

    public init(
        id: String, name: String, version: String, description: String,
        mode: PluginMode, keywords: [String], entry: String,
        author: String? = nil, icon: String? = nil,
        hotkey: String? = nil, config: [PluginConfigField]? = nil
    ) {
        self.id = id; self.name = name; self.version = version; self.description = description
        self.mode = mode; self.keywords = keywords; self.entry = entry
        self.author = author; self.icon = icon; self.hotkey = hotkey; self.config = config
    }
}

public struct PluginInstanceState: Codable, Sendable, Hashable, Equatable {
    public var isEnabled: Bool
    public var configValues: [String: String]

    public init(isEnabled: Bool = true, configValues: [String: String] = [:]) {
        self.isEnabled = isEnabled
        self.configValues = configValues
    }
}

public struct PluginStateSnapshot: Codable, Sendable, Hashable, Equatable {
    public var schemaVersion: Int
    public var plugins: [String: PluginInstanceState]

    public init(schemaVersion: Int = 1, plugins: [String: PluginInstanceState] = [:]) {
        self.schemaVersion = schemaVersion
        self.plugins = plugins
    }
}

public struct PluginDescriptor: Identifiable, Sendable, Hashable {
    public let id: String
    public let directoryURL: URL
    public let manifest: PluginManifest
    public let validationIssues: [String]
    public let nameLowercased: String
    public let descriptionLowercased: String
    public let keywordsLowercased: [String]
    public let isEnabled: Bool
    public let userConfig: [String: String]
    public var isValid: Bool { validationIssues.isEmpty }

    public init(
        id: String,
        directoryURL: URL,
        manifest: PluginManifest,
        validationIssues: [String],
        isEnabled: Bool = true,
        userConfig: [String: String] = [:]
    ) {
        self.id = id
        self.directoryURL = directoryURL
        self.manifest = manifest
        self.validationIssues = validationIssues
        self.nameLowercased = manifest.name.lowercased()
        self.descriptionLowercased = manifest.description.lowercased()
        self.keywordsLowercased = manifest.keywords.map { $0.lowercased() }
        self.isEnabled = isEnabled
        self.userConfig = userConfig
    }
}

public struct PluginExecutionResult: Sendable, Hashable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let durationMs: Int

    public init(exitCode: Int32, stdout: String, stderr: String, durationMs: Int) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationMs = durationMs
    }
}

public enum PluginSystem {
    static let stateLock = NSLock()

    public static func defaultPluginsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Lumakey", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
    }

    public static func stateFileURL(for rootDir: URL = defaultPluginsDirectory()) -> URL {
        let standardized = rootDir.standardizedFileURL
        if standardized.lastPathComponent == "Plugins" {
            return standardized.deletingLastPathComponent().appendingPathComponent("plugin-state.json")
        }
        return standardized.appendingPathComponent("plugin-state.json")
    }

    public static func isSafePluginID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 64 else { return false }
        return id.allSatisfy { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "-" }
    }

    public static func resolvedConfig(for manifest: PluginManifest, stored: [String: String]) -> [String: String] {
        var merged: [String: String] = [:]
        for field in manifest.config ?? [] {
            if let def = field.defaultValue { merged[field.key] = def }
        }
        for (k, v) in stored { merged[k] = v }
        return merged
    }

    public static func listPlugins(in rootDir: URL = defaultPluginsDirectory(), includeDisabled: Bool = true) -> [PluginDescriptor] {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: rootDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let snapshot = loadStateSnapshot(in: rootDir)
        return folders.compactMap { folder in
            let isDir = (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { return nil }
            let desc = loadPlugin(at: folder, snapshot: snapshot)
            return (!includeDisabled && !desc.isEnabled) ? nil : desc
        }.sorted { $0.id < $1.id }
    }

    public static func loadPlugin(at directoryURL: URL, in rootDir: URL? = nil) -> PluginDescriptor {
        let resolvedRoot = rootDir ?? directoryURL.deletingLastPathComponent()
        let snapshot = loadStateSnapshot(in: resolvedRoot)
        return loadPlugin(at: directoryURL, snapshot: snapshot)
    }

    static func loadPlugin(at directoryURL: URL, snapshot: PluginStateSnapshot) -> PluginDescriptor {
        let folderName = directoryURL.lastPathComponent
        let manifestURL = directoryURL.appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data)
        else {
            let fallback = PluginManifest(id: folderName, name: folderName, version: "0.0.0", description: "无效清单", mode: .script, keywords: [], entry: "")
            return PluginDescriptor(id: folderName, directoryURL: directoryURL, manifest: fallback, validationIssues: ["缺少或无法解析 plugin.json"])
        }
        let issues = validate(manifest: manifest, in: directoryURL)
        let inst = snapshot.plugins[manifest.id] ?? PluginInstanceState()
        let config = resolvedConfig(for: manifest, stored: inst.configValues)
        return PluginDescriptor(
            id: manifest.id,
            directoryURL: directoryURL,
            manifest: manifest,
            validationIssues: issues,
            isEnabled: inst.isEnabled,
            userConfig: config
        )
    }

    public static func validate(manifest: PluginManifest, in directoryURL: URL) -> [String] {
        var issues: [String] = []
        if !isSafePluginID(manifest.id) { issues.append("id 仅允许小写字母、数字与连字符") }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("name 不能为空") }
        if manifest.keywords.isEmpty { issues.append("keywords 至少包含一个触发词") }
        let entryURL = directoryURL.appendingPathComponent(manifest.entry).standardizedFileURL
        let rootPath = directoryURL.standardizedFileURL.path
        if manifest.entry.isEmpty || !entryURL.path.hasPrefix(rootPath + "/") {
            issues.append("entry 路径不合法或试图逃逸插件目录")
        } else if !FileManager.default.fileExists(atPath: entryURL.path) {
            issues.append("入口文件不存在：\(manifest.entry)")
        } else if !FileManager.default.isExecutableFile(atPath: entryURL.path) {
            issues.append("插件入口缺少可执行权限：\(manifest.entry)")
        }
        for field in manifest.config ?? [] {
            if field.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("config 存在空的 key 字段")
            }
            if field.type == .select && (field.options ?? []).isEmpty {
                issues.append("config 下拉项 '\(field.key)' 缺少 options 候选列表")
            }
        }
        return issues
    }
}
