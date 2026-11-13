import CryptoKit
import Foundation

public enum BackupArchiveService {
    public static let defaultMaxEmbeddedImageBytes: Int = 2 * 1024 * 1024
    static let typedConfigReservedNames: Set<String> = [
        "mos-config.json", "telemetry-v2.json", "telemetry-config.json"
    ]
    static let redactedWebDAVKeys: Set<String> = [
        "password", "passwd", "apppassword", "webdavpassword", "authpassword", "secret", "token"
    ]

    public static func defaultAppSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Lumakey", isDirectory: true)
    }

    public static func defaultBackupFileName(date: Date = Date()) -> String {
        var sec = time_t(date.timeIntervalSince1970)
        var local = tm()
        localtime_r(&sec, &local)
        return String(
            format: "lumakey-backup-%04d%02d%02d-%02d%02d%02d.%@",
            Int(local.tm_year) + 1900, Int(local.tm_mon) + 1, Int(local.tm_mday),
            Int(local.tm_hour), Int(local.tm_min), Int(local.tm_sec),
            BackupEnvelope.fileExtension
        )
    }

    public static func computePayloadSHA256(_ payload: BackupPayload) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let bytes = try enc.encode(payload)
        let digest = SHA256.hash(data: bytes)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func isSafeConfigFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128, !name.hasPrefix(".") else { return false }
        guard !name.contains("/"), !name.contains("\\"), !name.contains(".."), !name.contains("\0") else { return false }
        return name.lowercased().hasSuffix(".json")
    }

    public static func isSafeRelativePluginPath(_ path: String) -> Bool {
        guard !path.isEmpty, path.count <= 256 else { return false }
        guard !path.hasPrefix("/"), !path.hasPrefix("\\"), !path.hasPrefix("~") else { return false }
        guard !path.contains("\\"), !path.contains("\0") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    public static func exportBackupData(
        appSupportDirectory: URL = defaultAppSupportDirectory(),
        pluginsDirectory: URL? = nil,
        clipboardEntries: [ClipboardEntry] = [],
        mosConfig: MosConfig? = nil,
        telemetryConfig: SystemMonitorConfig? = nil,
        maxEmbeddedImageBytes: Int = defaultMaxEmbeddedImageBytes,
        appVersion: String = "0.7.0",
        createdAt: Date = Date()
    ) throws -> Data {
        let resolvedPluginsDir = pluginsDirectory ?? appSupportDirectory.appendingPathComponent("Plugins", isDirectory: true)
        let resolvedMos = mosConfig ?? MosConfig.load(from: appSupportDirectory.appendingPathComponent("mos-config.json"))
        let resolvedTelemetry = telemetryConfig ?? SystemMonitorConfig.load(from: appSupportDirectory.appendingPathComponent("telemetry-v2.json"))
        let rawConfigs = collectRawConfigFiles(in: appSupportDirectory)
        let clipboardRecords = encodePinnedClipboard(clipboardEntries, maxEmbeddedImageBytes: maxEmbeddedImageBytes)
        let pluginBundles = collectPluginBundles(in: resolvedPluginsDir)

        let draftPayload = BackupPayload(
            mosConfig: resolvedMos,
            telemetryConfig: resolvedTelemetry,
            rawConfigFiles: rawConfigs,
            pinnedClipboardItems: clipboardRecords,
            plugins: pluginBundles
        )
        let canonicalEnc = JSONEncoder()
        canonicalEnc.outputFormatting = [.sortedKeys]
        let normalizedPayload = try JSONDecoder().decode(BackupPayload.self, from: canonicalEnc.encode(draftPayload))
        let sha256 = try computePayloadSHA256(normalizedPayload)

        let iso = ISO8601DateFormatter()
        let envelope = BackupEnvelope(
            schemaVersion: BackupEnvelope.currentSchemaVersion,
            createdAtISO8601: iso.string(from: createdAt),
            appVersion: appVersion,
            hostName: ProcessInfo.processInfo.hostName,
            payloadSHA256: sha256,
            payload: normalizedPayload
        )
        let prettyEnc = JSONEncoder()
        prettyEnc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try prettyEnc.encode(envelope)
    }

    public static func inspectBackupData(_ data: Data) throws -> BackupInspectionSummary {
        let envelope = try decodeAndVerifyEnvelope(data)
        let p = envelope.payload
        let configNames = ["mos-config.json", "telemetry-v2.json"] + p.rawConfigFiles.keys.sorted()
        let skippedImages = p.pinnedClipboardItems.filter(\.skippedLargeImage).count
        return BackupInspectionSummary(
            schemaVersion: envelope.schemaVersion,
            createdAtISO8601: envelope.createdAtISO8601,
            appVersion: envelope.appVersion,
            hostName: envelope.hostName,
            payloadSHA256: envelope.payloadSHA256,
            archiveByteCount: data.count,
            configFileNames: configNames,
            pinnedClipboardCount: p.pinnedClipboardItems.count,
            skippedLargeImageCount: skippedImages,
            pluginIDs: p.plugins.map(\.id)
        )
    }

    public static func restoreBackupData(
        _ data: Data,
        options: BackupRestoreOptions = .all,
        appSupportDirectory: URL = defaultAppSupportDirectory(),
        pluginsDirectory: URL? = nil,
        clipboardImagesDirectory: URL? = nil
    ) throws -> BackupRestoreReport {
        let envelope = try decodeAndVerifyEnvelope(data)
        let payload = envelope.payload
        let resolvedPluginsDir = pluginsDirectory ?? appSupportDirectory.appendingPathComponent("Plugins", isDirectory: true)
        let resolvedClipDir = clipboardImagesDirectory ?? appSupportDirectory.appendingPathComponent("ClipboardPinned", isDirectory: true)

        try validatePayloadSafety(payload, appSupportDirectory: appSupportDirectory, pluginsDirectory: resolvedPluginsDir)

        var restoredConfigs: [String] = []
        if options.restoreConfigs {
            try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
            payload.mosConfig.save(to: appSupportDirectory.appendingPathComponent("mos-config.json"))
            payload.telemetryConfig.save(to: appSupportDirectory.appendingPathComponent("telemetry-v2.json"))
            restoredConfigs.append(contentsOf: ["mos-config.json", "telemetry-v2.json"])

            for name in payload.rawConfigFiles.keys.sorted() {
                guard let content = payload.rawConfigFiles[name] else { continue }
                let cleanContent = sanitizeConfigTextIfNeeded(fileName: name, rawText: content)
                let target = appSupportDirectory.appendingPathComponent(name, isDirectory: false)
                try Data(cleanContent.utf8).write(to: target, options: .atomic)
                restoredConfigs.append(name)
            }
        }

        var restoredClip: [ClipboardEntry] = []
        var skippedClip = 0
        if options.restoreClipboard {
            let decoded = try restorePinnedClipboard(payload.pinnedClipboardItems, imageDir: resolvedClipDir)
            restoredClip = decoded.entries
            skippedClip = decoded.skippedCount
        }

        var restoredPlugins: [String] = []
        if options.restorePlugins {
            restoredPlugins = try restorePlugins(
                payload.plugins, in: resolvedPluginsDir, overwrite: options.overwriteExistingPlugins
            )
        }

        return BackupRestoreReport(
            mosConfig: payload.mosConfig, telemetryConfig: payload.telemetryConfig,
            restoredConfigFileNames: restoredConfigs, restoredClipboardEntries: restoredClip,
            skippedClipboardCount: skippedClip, restoredPluginIDs: restoredPlugins
        )
    }
}
