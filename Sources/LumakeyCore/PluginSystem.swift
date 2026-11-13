import Foundation

public enum PluginMode: String, Codable, Sendable, Hashable {
    case script
    case view
}

public struct PluginManifest: Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let mode: PluginMode
    public let keywords: [String]
    public let entry: String

    public init(
        id: String,
        name: String,
        version: String,
        description: String,
        mode: PluginMode,
        keywords: [String],
        entry: String
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.mode = mode
        self.keywords = keywords
        self.entry = entry
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
    public var isValid: Bool { validationIssues.isEmpty }

    public init(id: String, directoryURL: URL, manifest: PluginManifest, validationIssues: [String]) {
        self.id = id
        self.directoryURL = directoryURL
        self.manifest = manifest
        self.validationIssues = validationIssues
        self.nameLowercased = manifest.name.lowercased()
        self.descriptionLowercased = manifest.description.lowercased()
        self.keywordsLowercased = manifest.keywords.map { $0.lowercased() }
    }
}

public struct PluginExecutionResult: Sendable, Hashable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let durationMs: Int
}

public enum PluginSystem {
    public static func defaultPluginsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Lumakey", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
    }

    public static func isSafePluginID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 64 else { return false }
        return id.allSatisfy { ch in
            (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch == "-"
        }
    }

    public static func listPlugins(in rootDir: URL = defaultPluginsDirectory()) -> [PluginDescriptor] {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: rootDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return folders.compactMap { folder in
            let isDir = (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { return nil }
            return loadPlugin(at: folder)
        }.sorted { $0.id < $1.id }
    }

    public static func loadPlugin(at directoryURL: URL) -> PluginDescriptor {
        let folderName = directoryURL.lastPathComponent
        let manifestURL = directoryURL.appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data)
        else {
            let fallback = PluginManifest(id: folderName, name: folderName, version: "0.0.0", description: "无效清单", mode: .script, keywords: [], entry: "")
            return PluginDescriptor(id: folderName, directoryURL: directoryURL, manifest: fallback, validationIssues: ["缺少或无法解析 plugin.json"])
        }
        let issues = validate(manifest: manifest, in: directoryURL)
        return PluginDescriptor(id: manifest.id, directoryURL: directoryURL, manifest: manifest, validationIssues: issues)
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
        } else if manifest.mode == .script && !FileManager.default.isExecutableFile(atPath: entryURL.path) {
            issues.append("脚本入口缺少可执行权限：\(manifest.entry)")
        }
        return issues
    }

    @discardableResult
    public static func scaffoldPlugin(
        id: String,
        name: String,
        keywords: [String],
        description: String,
        mode: PluginMode = .script,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws -> PluginDescriptor {
        guard isSafePluginID(id) else {
            throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法，仅支持小写字母、数字和连字符。")
        }
        let pluginDir = rootDir.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let entryName = "run.sh"
        let scriptContent = """
        #!/bin/zsh
        set -euo pipefail
        PAYLOAD="$(cat)"
        echo "[\(id)] ok: $PAYLOAD"
        """
        let scriptURL = pluginDir.appendingPathComponent(entryName)
        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let manifest = PluginManifest(
            id: id,
            name: name,
            version: "1.0.0",
            description: description,
            mode: mode,
            keywords: keywords.isEmpty ? [id] : keywords,
            entry: entryName
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(manifest)
        try jsonData.write(to: pluginDir.appendingPathComponent("plugin.json"), options: .atomic)
        return loadPlugin(at: pluginDir)
    }

    public static func runScriptPlugin(_ descriptor: PluginDescriptor, query: String) throws -> PluginExecutionResult {
        guard descriptor.isValid else {
            throw LumakeyError.pluginInvalid(descriptor.validationIssues.joined(separator: "；"))
        }
        let entryURL = descriptor.directoryURL.appendingPathComponent(descriptor.manifest.entry).standardizedFileURL
        let inputData = try JSONSerialization.data(withJSONObject: ["query": query])
        let result = try ProcessSupervisor.shared.run(
            executableURL: entryURL,
            currentDirectoryURL: descriptor.directoryURL,
            stdinData: inputData,
            timeoutSeconds: 8.0,
            maxOutputBytes: 65_536
        )
        if result.timedOut {
            throw LumakeyError.pluginExecutionFailed("插件进程执行超时（8s）已被自动终止")
        }
        return PluginExecutionResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            durationMs: result.durationMs
        )
    }

    public static let specMarkdown: String = """
    # Lumakey Plugin Specification (v1)
    - Directory: ~/Library/Application Support/Lumakey/Plugins/<id>/
    - Manifest (`plugin.json`): id (`[a-z0-9-]+`), name, version, description, mode (`script` | `view`), keywords (`[String]`), entry (relative path)
    - Script protocol: reads `{"query":"..."}` JSON from stdin, writes plain result text to stdout, exits 0.
    """
}
