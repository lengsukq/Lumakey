import CoreServices
import Foundation

public final class PluginDirectoryWatcher: @unchecked Sendable {
    private final class DebounceBox {
        let queue: DispatchQueue
        let debounceInterval: TimeInterval
        let onChange: @Sendable () -> Void
        var workItem: DispatchWorkItem?

        init(queue: DispatchQueue, debounceInterval: TimeInterval, onChange: @escaping @Sendable () -> Void) {
            self.queue = queue
            self.debounceInterval = debounceInterval
            self.onChange = onChange
        }

        func schedule() {
            workItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.workItem = nil
                self.onChange()
            }
            workItem = item
            queue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
        }
    }

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.queensu.lumakey.plugin-watcher", qos: .utility)
    private let box: DebounceBox
    private var stopped = false

    public var isWatching: Bool {
        queue.sync { !stopped && stream != nil }
    }

    public init?(
        directoryURL: URL = PluginSystem.defaultPluginsDirectory(),
        debounceInterval: TimeInterval = 0.35,
        onChange: @escaping @Sendable () -> Void
    ) {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let resolvedPath = directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        let box = DebounceBox(queue: queue, debounceInterval: debounceInterval, onChange: onChange)
        self.box = box

        let retained = Unmanaged.passRetained(box).toOpaque()
        var context = FSEventStreamContext(
            version: 0, info: retained, retain: nil,
            release: { ptr in if let ptr { Unmanaged<DebounceBox>.fromOpaque(ptr).release() } },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents
        )
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let paths = unsafeBitCast(eventPaths, to: NSArray.self)
            guard (0..<numEvents).contains(where: { (paths[$0] as? String)?.hasSuffix(".DS_Store") == false }) else { return }
            Unmanaged<DebounceBox>.fromOpaque(info).takeUnretainedValue().schedule()
        }
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, [resolvedPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags
        ) else {
            Unmanaged<DebounceBox>.fromOpaque(retained).release()
            return nil
        }

        self.stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    public func stop() {
        queue.sync {
            guard !stopped, let stream else { return }
            stopped = true
            box.workItem?.cancel()
            box.workItem = nil
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit {
        if !stopped, let stream {
            box.workItem?.cancel()
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}

extension PluginSystem {
    @discardableResult
    public static func scaffoldPlugin(
        id: String,
        name: String,
        keywords: [String],
        description: String,
        mode: PluginMode = .script,
        author: String? = nil,
        icon: String? = nil,
        hotkey: String? = nil,
        config: [PluginConfigField]? = nil,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws -> PluginDescriptor {
        guard isSafePluginID(id) else {
            throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法，仅支持小写字母、数字和连字符。")
        }
        let pluginDir = rootDir.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let entryName = "run.sh"
        let scriptContent: String
        if mode == .script {
            scriptContent = """
            #!/bin/zsh
            set -euo pipefail
            PAYLOAD="$(cat)"
            echo "[\(id)] ok: $PAYLOAD"
            """
        } else {
            scriptContent = """
            #!/bin/zsh
            set -euo pipefail
            PAYLOAD="$(cat)"
            Q="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract query raw -o - - 2>/dev/null || true)"
            Q_SAFE="${Q//\\"/\\\\\\"}"
            cat <<EOF
            {"title":"\(name)","subtitle":"[\(id)] ok · 查询参数: ${Q_SAFE}","badge":"VIEW","metrics":[{"key":"ID","value":"\(id)"},{"key":"Query","value":"${Q_SAFE:-empty}"}],"items":[{"title":"复制查询内容","subtitle":"${Q_SAFE:-无输入}","icon":"doc.on.doc","badge":"Copy","copyText":"${Q_SAFE}"}]}
            EOF
            """
        }
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
            entry: entryName,
            author: author,
            icon: icon,
            hotkey: hotkey,
            config: config
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(manifest)
        try jsonData.write(to: pluginDir.appendingPathComponent("plugin.json"), options: .atomic)
        return loadPlugin(at: pluginDir, in: rootDir)
    }

    public static func removePlugin(id: String, in rootDir: URL = defaultPluginsDirectory()) throws {
        guard isSafePluginID(id) else {
            throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法")
        }
        let pluginDir = rootDir.appendingPathComponent(id, isDirectory: true).standardizedFileURL
        guard pluginDir.path.hasPrefix(rootDir.standardizedFileURL.path + "/") else {
            throw LumakeyError.pluginInvalid("目标插件路径越界")
        }
        guard FileManager.default.fileExists(atPath: pluginDir.path) else {
            throw LumakeyError.pluginInvalid("未找到插件目录：\(id)")
        }
        try FileManager.default.removeItem(at: pluginDir)
        var snap = loadStateSnapshot(in: rootDir)
        if snap.plugins.removeValue(forKey: id) != nil {
            try? saveStateSnapshot(snap, in: rootDir)
        }
    }

    @discardableResult
    public static func importPluginDirectory(
        from sourceDir: URL,
        in rootDir: URL = defaultPluginsDirectory(),
        overwrite: Bool = true
    ) throws -> PluginDescriptor {
        let candidate = loadPlugin(at: sourceDir, snapshot: PluginStateSnapshot())
        guard isSafePluginID(candidate.manifest.id) else {
            throw LumakeyError.pluginInvalid("导入失败：plugin.json 中 id 不合法或缺失")
        }
        let targetDir = rootDir.appendingPathComponent(candidate.manifest.id, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: targetDir.path) {
            guard overwrite else { throw LumakeyError.pluginInvalid("插件 '\(candidate.manifest.id)' 已存在") }
            try FileManager.default.removeItem(at: targetDir)
        }
        try FileManager.default.copyItem(at: sourceDir, to: targetDir)
        let entryURL = targetDir.appendingPathComponent(candidate.manifest.entry).standardizedFileURL
        if entryURL.path.hasPrefix(targetDir.standardizedFileURL.path + "/"),
           FileManager.default.fileExists(atPath: entryURL.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entryURL.path)
        }
        return loadPlugin(at: targetDir, in: rootDir)
    }

    @discardableResult
    public static func exportPlugin(
        id: String,
        to destinationParentDir: URL,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws -> URL {
        guard isSafePluginID(id) else { throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法") }
        let sourceDir = rootDir.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourceDir.path) else {
            throw LumakeyError.pluginInvalid("插件 '\(id)' 不存在")
        }
        try FileManager.default.createDirectory(at: destinationParentDir, withIntermediateDirectories: true)
        let outDir = destinationParentDir.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: outDir.path) {
            try FileManager.default.removeItem(at: outDir)
        }
        try FileManager.default.copyItem(at: sourceDir, to: outDir)
        return outDir
    }
}
