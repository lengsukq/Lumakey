import CoreServices
import Foundation

public struct PluginKeyValue: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { "\(key):\(value)" }
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case key, label, value
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.key = (try? c.decode(String.self, forKey: .key))
            ?? (try? c.decode(String.self, forKey: .label))
            ?? ""
        self.value = try c.decode(String.self, forKey: .value)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(value, forKey: .value)
    }
}

public struct PluginViewItem: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { "\(title)|\(subtitle ?? "")|\(copyText ?? "")|\(openURL ?? "")" }
    public let title: String
    public let subtitle: String?
    public let icon: String?
    public let badge: String?
    public let copyText: String?
    public let openURL: String?
    public let commandArgs: [String]?

    public init(
        title: String, subtitle: String? = nil, icon: String? = nil, badge: String? = nil,
        copyText: String? = nil, openURL: String? = nil, commandArgs: [String]? = nil
    ) {
        self.title = title; self.subtitle = subtitle; self.icon = icon; self.badge = badge
        self.copyText = copyText; self.openURL = openURL; self.commandArgs = commandArgs
    }
}

public struct PluginViewPayload: Codable, Sendable, Equatable, Hashable {
    public let title: String
    public let subtitle: String?
    public let badge: String?
    public let markdown: String?
    public let metrics: [PluginKeyValue]?
    public let items: [PluginViewItem]?

    public init(
        title: String, subtitle: String? = nil, badge: String? = nil,
        markdown: String? = nil, metrics: [PluginKeyValue]? = nil, items: [PluginViewItem]? = nil
    ) {
        self.title = title; self.subtitle = subtitle; self.badge = badge
        self.markdown = markdown; self.metrics = metrics; self.items = items
    }

    public static func parse(from rawOutput: String) -> PluginViewPayload? {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", trimmed.last == "}",
              let data = trimmed.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PluginViewPayload.self, from: data),
              !payload.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return payload
    }
}

public struct PluginResolvedOutput: Sendable, Equatable, Hashable {
    public let pluginID: String
    public let pluginName: String
    public let mode: PluginMode
    public let execution: PluginExecutionResult
    public let viewPayload: PluginViewPayload?
    public let plainText: String
    public var isStructuredView: Bool { viewPayload != nil }

    public init(descriptor: PluginDescriptor, execution: PluginExecutionResult) {
        self.pluginID = descriptor.id
        self.pluginName = descriptor.manifest.name
        self.mode = descriptor.manifest.mode
        self.execution = execution
        if execution.exitCode == 0, let parsed = PluginViewPayload.parse(from: execution.stdout) {
            self.viewPayload = parsed
            self.plainText = Self.summarize(parsed)
        } else {
            self.viewPayload = nil
            self.plainText = execution.stdout.isEmpty ? execution.stderr : execution.stdout
        }
    }

    private static func summarize(_ payload: PluginViewPayload) -> String {
        var lines: [String] = [payload.title]
        if let sub = payload.subtitle, !sub.isEmpty { lines.append(sub) }
        for m in payload.metrics ?? [] { lines.append("\(m.key): \(m.value)") }
        for item in payload.items ?? [] {
            lines.append("• \(item.title)" + (item.subtitle.map { " — \($0)" } ?? ""))
        }
        if let md = payload.markdown, !md.isEmpty { lines.append(md) }
        return lines.joined(separator: "\n")
    }
}

extension PluginSystem {
    public static func loadStateSnapshot(in rootDir: URL = defaultPluginsDirectory()) -> PluginStateSnapshot {
        stateLock.withLock {
            let url = stateFileURL(for: rootDir)
            guard let data = try? Data(contentsOf: url),
                  let snap = try? JSONDecoder().decode(PluginStateSnapshot.self, from: data)
            else { return PluginStateSnapshot() }
            return snap
        }
    }

    public static func saveStateSnapshot(_ snapshot: PluginStateSnapshot, in rootDir: URL = defaultPluginsDirectory()) throws {
        try stateLock.withLock {
            let url = stateFileURL(for: rootDir)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        }
    }

    public static func isPluginEnabled(id: String, in rootDir: URL = defaultPluginsDirectory()) -> Bool {
        loadStateSnapshot(in: rootDir).plugins[id]?.isEnabled ?? true
    }

    public static func setPluginEnabled(id: String, isEnabled: Bool, in rootDir: URL = defaultPluginsDirectory()) throws {
        guard isSafePluginID(id) else { throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法") }
        var snap = loadStateSnapshot(in: rootDir)
        var inst = snap.plugins[id] ?? PluginInstanceState()
        inst.isEnabled = isEnabled
        snap.plugins[id] = inst
        try saveStateSnapshot(snap, in: rootDir)
    }

    public static func pluginConfig(id: String, in rootDir: URL = defaultPluginsDirectory()) -> [String: String] {
        loadStateSnapshot(in: rootDir).plugins[id]?.configValues ?? [:]
    }

    public static func updatePluginConfig(id: String, values: [String: String], in rootDir: URL = defaultPluginsDirectory()) throws {
        guard isSafePluginID(id) else { throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法") }
        var snap = loadStateSnapshot(in: rootDir)
        var inst = snap.plugins[id] ?? PluginInstanceState()
        inst.configValues = values
        snap.plugins[id] = inst
        try saveStateSnapshot(snap, in: rootDir)
    }

    public static func buildStdinContextData(
        for descriptor: PluginDescriptor,
        query: String,
        clipboardText: String = "",
        in rootDir: URL? = nil
    ) throws -> Data {
        let stateRoot = rootDir ?? descriptor.directoryURL.deletingLastPathComponent()
        let stored = pluginConfig(id: descriptor.id, in: stateRoot)
        let mergedConfig = resolvedConfig(for: descriptor.manifest, stored: descriptor.userConfig.merging(stored) { _, new in new })
        let payload: [String: Any] = [
            "query": query,
            "mode": descriptor.manifest.mode.rawValue,
            "config": mergedConfig,
            "clipboard": clipboardText
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    public static func runScriptPlugin(
        _ descriptor: PluginDescriptor,
        query: String,
        clipboardText: String = "",
        arguments: [String] = [],
        in rootDir: URL? = nil,
        timeoutSeconds: Double = 8.0
    ) throws -> PluginExecutionResult {
        guard descriptor.isValid else {
            throw LumakeyError.pluginInvalid(descriptor.validationIssues.joined(separator: "；"))
        }
        let stateRoot = rootDir ?? descriptor.directoryURL.deletingLastPathComponent()
        let enabledNow = descriptor.isEnabled && isPluginEnabled(id: descriptor.id, in: stateRoot)
        guard enabledNow else {
            throw LumakeyError.pluginExecutionFailed("插件 '\(descriptor.manifest.name)' 当前已禁用")
        }
        let entryURL = descriptor.directoryURL.appendingPathComponent(descriptor.manifest.entry).standardizedFileURL
        let inputData = try buildStdinContextData(for: descriptor, query: query, clipboardText: clipboardText, in: stateRoot)
        let result = try ProcessSupervisor.shared.run(
            executableURL: entryURL,
            arguments: arguments,
            currentDirectoryURL: descriptor.directoryURL,
            stdinData: inputData,
            timeoutSeconds: timeoutSeconds,
            maxOutputBytes: 131_072
        )
        if result.timedOut {
            throw LumakeyError.pluginExecutionFailed("插件进程执行超时（\(Int(timeoutSeconds))s）已被自动终止")
        }
        return PluginExecutionResult(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, durationMs: result.durationMs)
    }

    public static func runPluginSync(
        _ descriptor: PluginDescriptor,
        query: String,
        clipboardText: String = "",
        arguments: [String] = [],
        in rootDir: URL? = nil,
        timeoutSeconds: Double = 8.0
    ) throws -> PluginResolvedOutput {
        let exec = try runScriptPlugin(descriptor, query: query, clipboardText: clipboardText, arguments: arguments, in: rootDir, timeoutSeconds: timeoutSeconds)
        return PluginResolvedOutput(descriptor: descriptor, execution: exec)
    }

    public static func runPluginAsync(
        _ descriptor: PluginDescriptor,
        query: String,
        clipboardText: String = "",
        arguments: [String] = [],
        in rootDir: URL? = nil,
        timeoutSeconds: Double = 8.0
    ) async throws -> PluginResolvedOutput {
        try await Task.detached(priority: .userInitiated) {
            try runPluginSync(descriptor, query: query, clipboardText: clipboardText, arguments: arguments, in: rootDir, timeoutSeconds: timeoutSeconds)
        }.value
    }
}
