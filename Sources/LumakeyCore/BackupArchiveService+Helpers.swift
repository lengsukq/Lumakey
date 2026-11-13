import CoreGraphics
import Foundation

extension BackupArchiveService {
    static func decodeAndVerifyEnvelope(_ data: Data) throws -> BackupEnvelope {
        let envelope: BackupEnvelope
        do {
            envelope = try JSONDecoder().decode(BackupEnvelope.self, from: data)
        } catch {
            throw BackupArchiveError.corruptedArchive(error.localizedDescription)
        }
        guard envelope.schemaVersion == BackupEnvelope.currentSchemaVersion else {
            throw BackupArchiveError.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        let computed = try computePayloadSHA256(envelope.payload)
        guard !envelope.payloadSHA256.isEmpty,
              computed.lowercased() == envelope.payloadSHA256.lowercased() else {
            throw BackupArchiveError.checksumMismatch(expected: envelope.payloadSHA256, actual: computed)
        }
        return envelope
    }

    static func validatePayloadSafety(
        _ payload: BackupPayload,
        appSupportDirectory: URL,
        pluginsDirectory: URL
    ) throws {
        let appRootPath = appSupportDirectory.standardizedFileURL.path
        for (name, rawJSON) in payload.rawConfigFiles {
            guard isSafeConfigFileName(name) else {
                throw BackupArchiveError.unsafePath(name)
            }
            let target = appSupportDirectory.appendingPathComponent(name, isDirectory: false).standardizedFileURL
            guard target.deletingLastPathComponent().path == appRootPath else {
                throw BackupArchiveError.unsafePath(name)
            }
            guard (try? JSONSerialization.jsonObject(with: Data(rawJSON.utf8))) != nil else {
                throw BackupArchiveError.corruptedArchive("配置文件 \(name) JSON 格式无效")
            }
        }

        let pluginsRootPath = pluginsDirectory.standardizedFileURL.path
        for bundle in payload.plugins {
            guard PluginSystem.isSafePluginID(bundle.id) else {
                throw BackupArchiveError.unsafePluginID(bundle.id)
            }
            let bundleRoot = pluginsDirectory.appendingPathComponent(bundle.id, isDirectory: true).standardizedFileURL
            guard bundleRoot.deletingLastPathComponent().path == pluginsRootPath else {
                throw BackupArchiveError.unsafePluginID(bundle.id)
            }
            for file in bundle.files {
                guard isSafeRelativePluginPath(file.relativePath) else {
                    throw BackupArchiveError.unsafePath("\(bundle.id)/\(file.relativePath)")
                }
                let fileURL = bundleRoot.appendingPathComponent(file.relativePath, isDirectory: false).standardizedFileURL
                guard fileURL.path.hasPrefix(bundleRoot.path + "/") else {
                    throw BackupArchiveError.unsafePath("\(bundle.id)/\(file.relativePath)")
                }
                guard Data(base64Encoded: file.contentBase64) != nil else {
                    throw BackupArchiveError.corruptedArchive("插件文件 \(bundle.id)/\(file.relativePath) Base64 无效")
                }
            }
        }
    }

    static func collectRawConfigFiles(in appSupportDirectory: URL) -> [String: String] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: appSupportDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var result: [String: String] = [:]
        for url in urls {
            let name = url.lastPathComponent
            guard isSafeConfigFileName(name), !typedConfigReservedNames.contains(name.lowercased()) else { continue }
            guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  vals.isRegularFile == true, vals.isSymbolicLink != true,
                  let data = try? Data(contentsOf: url),
                  (try? JSONSerialization.jsonObject(with: data)) != nil,
                  let rawText = String(data: data, encoding: .utf8) else { continue }
            result[name] = sanitizeConfigTextIfNeeded(fileName: name, rawText: rawText)
        }
        return result
    }

    static func sanitizeConfigTextIfNeeded(fileName: String, rawText: String) -> String {
        guard fileName.lowercased().contains("webdav"),
              let obj = try? JSONSerialization.jsonObject(with: Data(rawText.utf8)) as? [String: Any] else {
            return rawText
        }
        let cleaned = stripRedactedKeys(in: obj)
        guard let cleanData = try? JSONSerialization.data(withJSONObject: cleaned, options: [.prettyPrinted, .sortedKeys]),
              let cleanText = String(data: cleanData, encoding: .utf8) else {
            return rawText
        }
        return cleanText
    }

    private static func stripRedactedKeys(in dict: [String: Any]) -> [String: Any] {
        var next: [String: Any] = [:]
        for (k, v) in dict where !redactedWebDAVKeys.contains(k.lowercased()) {
            if let sub = v as? [String: Any] {
                next[k] = stripRedactedKeys(in: sub)
            } else {
                next[k] = v
            }
        }
        return next
    }

    static func encodePinnedClipboard(_ entries: [ClipboardEntry], maxEmbeddedImageBytes: Int) -> [BackupClipboardRecord] {
        let iso = ISO8601DateFormatter()
        return entries.filter(\.isPinned).compactMap { item in
            let ts = iso.string(from: item.capturedAt)
            switch item.payloadKind {
            case .text:
                return BackupClipboardRecord(id: item.id.uuidString, title: item.title, subtitle: item.subtitle, kind: .text, capturedAtISO8601: ts, textValue: item.textValue)
            case .colorHex(let hex):
                return BackupClipboardRecord(id: item.id.uuidString, title: item.title, subtitle: item.subtitle, kind: .colorHex, capturedAtISO8601: ts, textValue: item.textValue ?? hex, colorHex: hex)
            case .file(let url):
                return BackupClipboardRecord(id: item.id.uuidString, title: item.title, subtitle: item.subtitle, kind: .file, capturedAtISO8601: ts, filePath: url.path)
            case .image(let url, let dims):
                guard let imgData = try? Data(contentsOf: url), !imgData.isEmpty else { return nil }
                let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
                if imgData.count > maxEmbeddedImageBytes {
                    return BackupClipboardRecord(
                        id: item.id.uuidString, title: item.title, subtitle: item.subtitle, kind: .image,
                        capturedAtISO8601: ts, imageWidth: Double(dims.width), imageHeight: Double(dims.height),
                        imageExtension: ext, skippedLargeImage: true, originalByteSize: imgData.count
                    )
                }
                return BackupClipboardRecord(
                    id: item.id.uuidString, title: item.title, subtitle: item.subtitle, kind: .image,
                    capturedAtISO8601: ts, imageBase64: imgData.base64EncodedString(),
                    imageWidth: Double(dims.width), imageHeight: Double(dims.height),
                    imageExtension: ext, skippedLargeImage: false, originalByteSize: imgData.count
                )
            }
        }
    }

    static func restorePinnedClipboard(
        _ records: [BackupClipboardRecord],
        imageDir: URL
    ) throws -> (entries: [ClipboardEntry], skippedCount: Int) {
        let iso = ISO8601DateFormatter()
        var entries: [ClipboardEntry] = []
        var skipped = 0

        for rec in records {
            let uuid = UUID(uuidString: rec.id) ?? UUID()
            let date = iso.date(from: rec.capturedAtISO8601) ?? Date()
            switch rec.kind {
            case .text:
                entries.append(ClipboardEntry(id: uuid, title: rec.title, subtitle: rec.subtitle, textValue: rec.textValue, capturedAt: date, isPinned: true, payloadKind: .text))
            case .colorHex:
                let hex = rec.colorHex ?? rec.textValue ?? "#000000"
                entries.append(ClipboardEntry(id: uuid, title: rec.title, subtitle: rec.subtitle, textValue: rec.textValue ?? hex, capturedAt: date, isPinned: true, payloadKind: .colorHex(hex)))
            case .file:
                if let p = rec.filePath, !p.isEmpty {
                    let u = URL(fileURLWithPath: p)
                    entries.append(ClipboardEntry(id: uuid, title: rec.title, subtitle: rec.subtitle, fileURL: u, capturedAt: date, isPinned: true, payloadKind: .file(u)))
                } else { skipped += 1 }
            case .image:
                guard !rec.skippedLargeImage, let b64 = rec.imageBase64, let imgData = Data(base64Encoded: b64) else {
                    skipped += 1; continue
                }
                try FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
                let rawExt = (rec.imageExtension ?? "png").filter { $0.isLetter || $0.isNumber }
                let ext = rawExt.isEmpty ? "png" : rawExt
                let imgURL = imageDir.appendingPathComponent("pinned-\(uuid.uuidString).\(ext)", isDirectory: false)
                try imgData.write(to: imgURL, options: .atomic)
                let fallbackSize = CGSize(width: rec.imageWidth ?? 0, height: rec.imageHeight ?? 0)
                let dims = MediaClassifier.readImageDimensions(at: imgURL) ?? fallbackSize
                entries.append(ClipboardEntry(id: uuid, title: rec.title, subtitle: rec.subtitle, fileURL: imgURL, capturedAt: date, isPinned: true, payloadKind: .image(imgURL, dims)))
            }
        }
        return (entries, skipped)
    }

    static func collectPluginBundles(in pluginsDir: URL) -> [BackupPluginBundle] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(
            at: pluginsDir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var bundles: [BackupPluginBundle] = []
        for folder in folders {
            let id = folder.lastPathComponent
            guard PluginSystem.isSafePluginID(id),
                  let vals = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  vals.isDirectory == true, vals.isSymbolicLink != true else { continue }

            let rootStd = folder.resolvingSymlinksInPath().standardizedFileURL.path
            guard let enumerator = fm.enumerator(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: []
            ) else { continue }

            var files: [BackupPluginFileRecord] = []
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == ".DS_Store" { continue }
                guard let fVals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                      fVals.isSymbolicLink != true, fVals.isRegularFile == true else { continue }
                let fileStd = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
                guard fileStd.hasPrefix(rootStd + "/") else { continue }
                let rel = String(fileStd.dropFirst(rootStd.count + 1))
                guard isSafeRelativePluginPath(rel), let data = try? Data(contentsOf: fileURL) else { continue }
                let perms = ((try? fm.attributesOfItem(atPath: fileStd)[.posixPermissions]) as? Int) ?? 0o644
                let exec = (perms & 0o111) != 0 || fm.isExecutableFile(atPath: fileStd)
                files.append(BackupPluginFileRecord(relativePath: rel, contentBase64: data.base64EncodedString(), posixPermissions: perms & 0o777, isExecutable: exec))
            }
            files.sort { $0.relativePath < $1.relativePath }
            if !files.isEmpty { bundles.append(BackupPluginBundle(id: id, files: files)) }
        }
        return bundles.sorted { $0.id < $1.id }
    }

    static func restorePlugins(_ bundles: [BackupPluginBundle], in pluginsDir: URL, overwrite: Bool) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        var restoredIDs: [String] = []

        for bundle in bundles {
            let targetDir = pluginsDir.appendingPathComponent(bundle.id, isDirectory: true).standardizedFileURL
            if fm.fileExists(atPath: targetDir.path) {
                guard overwrite else { continue }
                try fm.removeItem(at: targetDir)
            }
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
            for file in bundle.files {
                guard let content = Data(base64Encoded: file.contentBase64) else {
                    throw BackupArchiveError.corruptedArchive("插件文件解码失败：\(bundle.id)/\(file.relativePath)")
                }
                let destURL = targetDir.appendingPathComponent(file.relativePath, isDirectory: false).standardizedFileURL
                try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: destURL, options: .atomic)
                let mode = (file.isExecutable || (file.posixPermissions & 0o111) != 0) ? 0o755 : 0o644
                try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: destURL.path)
            }
            restoredIDs.append(bundle.id)
        }
        return restoredIDs
    }
}
