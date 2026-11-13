import Foundation
import LumakeyCore

private final class MockWebDAVStore: @unchecked Sendable {
    static let shared = MockWebDAVStore()

    private let lock = NSLock()
    private var expectedAuthHeader: String = ""
    private var validRootPrefix: String = "/dav/"
    private var collections: Set<String> = ["/dav/"]
    private var files: [String: (data: Data, modified: Date)] = [:]
    private(set) var recordedMethods: [String] = []

    func reset(username: String, password: String, rootPrefix: String = "/dav/") {
        lock.withLock {
            let token = Data("\(username):\(password)".utf8).base64EncodedString()
            expectedAuthHeader = "Basic \(token)"
            validRootPrefix = rootPrefix
            collections = [rootPrefix]
            files = [:]
            recordedMethods = []
        }
    }

    func handle(request: URLRequest) -> (statusCode: Int, headers: [String: String], body: Data) {
        lock.withLock {
            let method = (request.httpMethod ?? "GET").uppercased()
            let rawPath = request.url?.path ?? "/"
            let isDirHint = request.url?.absoluteString.hasSuffix("/") == true
            let normDirPath = rawPath.hasSuffix("/") ? rawPath : (rawPath + "/")
            recordedMethods.append("\(method) \( isDirHint ? normDirPath : rawPath )")

            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            guard auth == expectedAuthHeader else {
                return (401, ["WWW-Authenticate": "Basic realm=\"MockDAV\""], Data("Unauthorized".utf8))
            }
            guard normDirPath.hasPrefix(validRootPrefix) || rawPath.hasPrefix(validRootPrefix) else {
                return (404, [:], Data("Not Found".utf8))
            }

            switch method {
            case "PROPFIND":
                let depth = request.value(forHTTPHeaderField: "Depth") ?? "1"
                guard collections.contains(normDirPath) else {
                    return (404, [:], Data("Collection Not Found".utf8))
                }
                let xml = buildMultiStatusXML(dirPath: normDirPath, depth: depth)
                return (207, ["Content-Type": "application/xml; charset=utf-8"], Data(xml.utf8))

            case "MKCOL":
                if collections.contains(normDirPath) {
                    return (405, [:], Data("Already Exists".utf8))
                }
                let parent = parentCollectionPath(of: normDirPath)
                guard collections.contains(parent) else {
                    return (409, [:], Data("Parent Missing".utf8))
                }
                collections.insert(normDirPath)
                return (201, [:], Data())

            case "PUT":
                let parent = parentCollectionPath(of: rawPath)
                guard collections.contains(parent) else {
                    return (409, [:], Data("Parent Missing".utf8))
                }
                let bodyData = Self.extractBody(from: request)
                let existed = files[rawPath] != nil
                files[rawPath] = (data: bodyData, modified: Date())
                return (existed ? 204 : 201, [:], Data())

            case "GET":
                guard let entry = files[rawPath] else {
                    return (404, [:], Data("Not Found".utf8))
                }
                return (200, ["Content-Type": "application/octet-stream"], entry.data)

            case "DELETE":
                guard files.removeValue(forKey: rawPath) != nil else {
                    return (404, [:], Data("Not Found".utf8))
                }
                return (204, [:], Data())

            default:
                return (405, [:], Data())
            }
        }
    }

    private func parentCollectionPath(of path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let idx = trimmed.lastIndex(of: "/") else { return "/" }
        return String(trimmed[...idx])
    }

    private func buildMultiStatusXML(dirPath: String, depth: String) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"

        var rows = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>\(dirPath)</d:href>
            <d:propstat>
              <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        """
        if depth != "0" {
            for (filePath, info) in files.sorted(by: { $0.key < $1.key }) {
                guard parentCollectionPath(of: filePath) == dirPath else { continue }
                let modStr = df.string(from: info.modified)
                rows += """
                  <d:response>
                    <d:href>\(filePath)</d:href>
                    <d:propstat>
                      <d:prop>
                        <d:resourcetype/>
                        <d:getcontentlength>\(info.data.count)</d:getcontentlength>
                        <d:getlastmodified>\(modStr)</d:getlastmodified>
                      </d:prop>
                      <d:status>HTTP/1.1 200 OK</d:status>
                    </d:propstat>
                  </d:response>
                """
            }
        }
        rows += "\n</d:multistatus>"
        return rows
    }

    private static func extractBody(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var out = Data()
        let bufSize = 16_384
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufSize)
            if readCount > 0 { out.append(buffer, count: readCount) }
            else { break }
        }
        return out
    }
}

private final class MockWebDAVURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result = MockWebDAVStore.shared.handle(request: request)
        let url = request.url ?? URL(string: "https://dav.mock.local/")!
        let response = HTTPURLResponse(
            url: url, statusCode: result.statusCode, httpVersion: "HTTP/1.1", headerFields: result.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !result.body.isEmpty {
            client?.urlProtocol(self, didLoad: result.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class AsyncTestBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

private func runBlockingAsync<T>(_ block: @escaping @Sendable () async throws -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    let box = AsyncTestBox<T>()
    Task.detached {
        do { box.result = .success(try await block()) }
        catch { box.result = .failure(error) }
        sem.signal()
    }
    sem.wait()
    return try box.result!.get()
}

func testV070BackupAndWebDAV() throws {
    let root = try makeTempDir("v070-backup")
    defer { try? FileManager.default.removeItem(at: root) }

    let srcSupport = root.appendingPathComponent("src-support", isDirectory: true)
    let srcPlugins = srcSupport.appendingPathComponent("Plugins", isDirectory: true)
    let dstSupport = root.appendingPathComponent("dst-support", isDirectory: true)
    let dstPlugins = dstSupport.appendingPathComponent("Plugins", isDirectory: true)
    let dstClipDir = root.appendingPathComponent("dst-clip", isDirectory: true)
    try FileManager.default.createDirectory(at: srcPlugins, withIntermediateDirectories: true)

    let customMos = MosConfig(
        enabled: true, reverseWheelDirection: false, smoothScroll: true,
        stepPixels: 54.0, smoothness: 0.28, shiftHorizontal: true, optionBoost: false,
        excludedBundleIDs: ["com.valve.steam"]
    )
    customMos.save(to: srcSupport.appendingPathComponent("mos-config.json"))

    var customPulse = SystemMonitorConfig()
    customPulse.floatingEnabled = true
    customPulse.showInMenuBar = true
    customPulse.displayMode = .alwaysExpanded
    customPulse.menuShowFreq = true
    customPulse.save(to: srcSupport.appendingPathComponent("telemetry-v2.json"))

    try #"{"launcher":"opt+space"}"#.write(to: srcSupport.appendingPathComponent("hotkeys.json"), atomically: true, encoding: .utf8)
    try #"[{"keyword":";hi","body":"Hello"}]"#.write(to: srcSupport.appendingPathComponent("snippets.json"), atomically: true, encoding: .utf8)
    try #"{"serverURL":"https://dav.jianguoyun.com/dav/","username":"alice@example.com","password":"PLAIN_SECRET_MUST_NOT_LEAK"}"#
        .write(to: srcSupport.appendingPathComponent("webdav-config.json"), atomically: true, encoding: .utf8)

    let smallImgURL = root.appendingPathComponent("small-pin.png")
    try renderTextPNG(text: "BACKUP PIN", to: smallImgURL)
    let hugeImgURL = root.appendingPathComponent("huge-pin.png")
    try Data(repeating: 0xAB, count: 2_200_000).write(to: hugeImgURL)

    let clipItems: [ClipboardEntry] = [
        ClipboardEntry(title: "kubectl", subtitle: "文本", textValue: "kubectl get pods -A", isPinned: true, payloadKind: .text),
        ClipboardEntry(title: "#38BDF8", subtitle: "色值", textValue: "#38BDF8", isPinned: true, payloadKind: .colorHex("#38BDF8")),
        ClipboardEntry(title: "小尺寸钉图", subtitle: "small", fileURL: smallImgURL, isPinned: true, payloadKind: .image(smallImgURL, CGSize(width: 480, height: 140))),
        ClipboardEntry(title: "超2MB大图", subtitle: "huge", fileURL: hugeImgURL, isPinned: true, payloadKind: .image(hugeImgURL, CGSize(width: 2400, height: 1600))),
        ClipboardEntry(title: "未收藏临时文本", subtitle: "transient", textValue: "ignore-me", isPinned: false, payloadKind: .text)
    ]

    _ = try PluginSystem.scaffoldPlugin(
        id: "backup-echo", name: "Backup Echo", keywords: ["becho"],
        description: "Test backup plugin", mode: .script, in: srcPlugins
    )
    let nestedAsset = srcPlugins.appendingPathComponent("backup-echo/assets/note.txt")
    try FileManager.default.createDirectory(at: nestedAsset.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "asset-ok".write(to: nestedAsset, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: nestedAsset.path)

    let archiveData = try BackupArchiveService.exportBackupData(
        appSupportDirectory: srcSupport, pluginsDirectory: srcPlugins, clipboardEntries: clipItems
    )
    let archiveString = String(data: archiveData, encoding: .utf8) ?? ""
    check(!archiveString.contains("PLAIN_SECRET_MUST_LEAK") && !archiveString.contains("PLAIN_SECRET_MUST_NOT_LEAK"), "WebDAV plaintext password stripped on export")
    check(!archiveString.contains("ignore-me"), "Unpinned clipboard entry excluded from export")

    let summary = try BackupArchiveService.inspectBackupData(archiveData)
    check(summary.schemaVersion == 1, "BackupEnvelope schemaVersion == 1")
    check(summary.configCount == 5, "Expected 5 configs (mos + telemetry + 3 json), got \(summary.configCount)")
    check(summary.pinnedClipboardCount == 4, "Expected 4 pinned clipboard items, got \(summary.pinnedClipboardCount)")
    check(summary.skippedLargeImageCount == 1, "Image > 2MB skipped from Base64 embedding")
    check(summary.pluginIDs == ["backup-echo"], "Exported plugin bundle backup-echo")

    let tamperedText = archiveString.replacingOccurrences(of: "kubectl get pods -A", with: "kubectl get pods -X")
    var caughtTamper = false
    do {
        _ = try BackupArchiveService.inspectBackupData(Data(tamperedText.utf8))
    } catch BackupArchiveError.checksumMismatch {
        caughtTamper = true
    }
    check(caughtTamper, "Tampered payload bytes caught by SHA-256 checksum verification")

    var maliciousEnv = try JSONDecoder().decode(BackupEnvelope.self, from: archiveData)
    maliciousEnv.payload.plugins = [
        BackupPluginBundle(id: "backup-echo", files: [
            BackupPluginFileRecord(relativePath: "../../escape.sh", contentBase64: Data("echo pwn".utf8).base64EncodedString(), posixPermissions: 0o755, isExecutable: true)
        ])
    ]
    maliciousEnv.payloadSHA256 = try BackupArchiveService.computePayloadSHA256(maliciousEnv.payload)
    let maliciousData = try JSONEncoder().encode(maliciousEnv)
    var caughtTraversal = false
    do {
        _ = try BackupArchiveService.restoreBackupData(maliciousData, appSupportDirectory: dstSupport, pluginsDirectory: dstPlugins)
    } catch BackupArchiveError.unsafePath {
        caughtTraversal = true
    }
    check(caughtTraversal, "Malicious ../ plugin path traversal rejected before write")

    var badIDEnv = try JSONDecoder().decode(BackupEnvelope.self, from: archiveData)
    badIDEnv.payload.plugins = [BackupPluginBundle(id: "../Bad_ID", files: [])]
    badIDEnv.payloadSHA256 = try BackupArchiveService.computePayloadSHA256(badIDEnv.payload)
    var caughtBadID = false
    do {
        _ = try BackupArchiveService.restoreBackupData(try JSONEncoder().encode(badIDEnv), appSupportDirectory: dstSupport, pluginsDirectory: dstPlugins)
    } catch BackupArchiveError.unsafePluginID {
        caughtBadID = true
    }
    check(caughtBadID, "Invalid plugin ID rejected by PluginSystem.isSafePluginID")

    let report = try BackupArchiveService.restoreBackupData(
        archiveData, appSupportDirectory: dstSupport, pluginsDirectory: dstPlugins, clipboardImagesDirectory: dstClipDir
    )
    check(MosConfig.load(from: dstSupport.appendingPathComponent("mos-config.json")) == customMos, "Restored MosConfig matches")
    check(SystemMonitorConfig.load(from: dstSupport.appendingPathComponent("telemetry-v2.json")) == customPulse, "Restored SystemMonitorConfig matches")
    check(FileManager.default.fileExists(atPath: dstSupport.appendingPathComponent("hotkeys.json").path), "Restored hotkeys.json")
    check(FileManager.default.fileExists(atPath: dstSupport.appendingPathComponent("snippets.json").path), "Restored snippets.json")
    check(report.restoredClipboardEntries.count == 3 && report.skippedClipboardCount == 1, "Restored 3 valid pinned clipboard entries and skipped 1 >2MB image")

    let restoredImgEntry = report.restoredClipboardEntries.first {
        if case .image = $0.payloadKind { return true }
        return false
    }
    check(restoredImgEntry?.fileURL.flatMap { MediaClassifier.readImageDimensions(at: $0) } == CGSize(width: 480, height: 140), "Restored embedded PNG dimensions intact")

    let restoredPluginDir = dstPlugins.appendingPathComponent("backup-echo")
    let loadedPlugin = PluginSystem.loadPlugin(at: restoredPluginDir)
    check(loadedPlugin.isValid, "Restored plugin passes validation: \(loadedPlugin.validationIssues)")
    let scriptPath = restoredPluginDir.appendingPathComponent("run.sh").path
    let perms = (try FileManager.default.attributesOfItem(atPath: scriptPath)[.posixPermissions] as? Int) ?? 0
    check((perms & 0o777) == 0o755 && FileManager.default.isExecutableFile(atPath: scriptPath), "Restored script has 0o755 executable permission")
    let execRes = try PluginSystem.runScriptPlugin(loadedPlugin, query: "hello")
    check(execRes.exitCode == 0 && execRes.stdout.contains("[backup-echo] ok:"), "Restored executable plugin runs cleanly")

    let testKeychainService = "app.lumakey.macos.webdav.check.\(UUID().uuidString)"
    defer { try? WebDAVKeychainStore.deletePassword(account: "alice@example.com", service: testKeychainService) }
    try WebDAVKeychainStore.savePassword("app-pass-1", account: "alice@example.com", service: testKeychainService)
    check(try WebDAVKeychainStore.loadPassword(account: "alice@example.com", service: testKeychainService) == "app-pass-1", "Keychain initial save/load")
    try WebDAVKeychainStore.savePassword("app-pass-2", account: "alice@example.com", service: testKeychainService)
    check(try WebDAVKeychainStore.loadPassword(account: "alice@example.com", service: testKeychainService) == "app-pass-2", "Keychain SecItemUpdate")
    try WebDAVKeychainStore.deletePassword(account: "alice@example.com", service: testKeychainService)
    check(try WebDAVKeychainStore.loadPassword(account: "alice@example.com", service: testKeychainService) == nil, "Keychain SecItemDelete")

    let upperCaseXML = Data("""
    <?xml version="1.0" encoding="utf-8"?>
    <D:multistatus xmlns:D="DAV:">
      <D:response>
        <D:href>/dav/LumakeyBackups/</D:href>
        <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
      </D:response>
      <D:response>
        <D:href>/dav/LumakeyBackups/readme.txt</D:href>
        <D:propstat><D:prop><D:getcontentlength>12</D:getcontentlength></D:prop></D:propstat>
      </D:response>
      <D:response>
        <D:href>/dav/LumakeyBackups/lumakey-backup-20261113-090000.lumakeybackup</D:href>
        <D:propstat><D:prop><D:resourcetype/><D:getcontentlength>1024</D:getcontentlength><D:getlastmodified>Fri, 13 Nov 2026 09:00:00 GMT</D:getlastmodified></D:prop></D:propstat>
      </D:response>
      <dav:response xmlns:dav="DAV:">
        <dav:href>/dav/LumakeyBackups/lumakey-backup-20261113-113000.lumakeybackup</dav:href>
        <dav:propstat><dav:prop><dav:resourcetype/><dav:getcontentlength>2048</dav:getcontentlength><dav:getlastmodified>Fri, 13 Nov 2026 11:30:00 GMT</dav:getlastmodified></dav:prop></dav:propstat>
      </dav:response>
    </D:multistatus>
    """.utf8)
    let parsedItems = try WebDAVMultiStatusParser.parse(
        xmlData: upperCaseXML, baseURL: URL(string: "https://nas.local:5006/dav/LumakeyBackups/")!
    )
    check(parsedItems.count == 2, "207 XML parser filtered out collection & .txt, kept 2 .lumakeybackup files")
    check(parsedItems[0].fileName == "lumakey-backup-20261113-113000.lumakeybackup" && parsedItems[0].sizeBytes == 2048, "207 XML sorted newest first across D:/dav: prefixes")

    MockWebDAVStore.shared.reset(username: "alice", password: "correct-app-password", rootPrefix: "/dav/")
    let sessionCfg = URLSessionConfiguration.ephemeral
    sessionCfg.protocolClasses = [MockWebDAVURLProtocol.self]

    try runBlockingAsync {
        let baseCfg = WebDAVConfig(
            serverURL: "https://dav.mock.local/dav/",
            username: "alice",
            remoteDirectory: "LumakeyBackups/MacStudio",
            keepLatestCount: 2
        )

        let badAuthClient = WebDAVClient(config: baseCfg, password: "wrong-password", sessionConfiguration: sessionCfg)
        var got401 = false
        do { _ = try await badAuthClient.testConnection() }
        catch WebDAVError.unauthorized(let code) { got401 = (code == 401) }
        check(got401, "WebDAVClient 401 Basic Auth rejection")

        let badPathCfg = WebDAVConfig(serverURL: "https://dav.mock.local/wrong-root/", username: "alice")
        let badPathClient = WebDAVClient(config: badPathCfg, password: "correct-app-password", sessionConfiguration: sessionCfg)
        var got404 = false
        do { _ = try await badPathClient.testConnection() }
        catch WebDAVError.notFound { got404 = true }
        check(got404, "WebDAVClient 404 root path detection")

        let client = WebDAVClient(config: baseCfg, password: "correct-app-password", sessionConfiguration: sessionCfg)
        let connMsg = try await client.testConnection()
        check(connMsg.contains("207"), "WebDAVClient testConnection PROPFIND 207 OK: \(connMsg)")

        try await client.ensureRemoteDirectory()
        try await client.ensureRemoteDirectory()

        _ = try await client.uploadBackup(data: archiveData, fileName: "lumakey-backup-20261113-100001.lumakeybackup")
        _ = try await client.uploadBackup(data: archiveData, fileName: "lumakey-backup-20261113-100002.lumakeybackup")
        _ = try await client.uploadBackup(data: archiveData, fileName: "lumakey-backup-20261113-100003.lumakeybackup")

        let remoteBackups = try await client.listBackups()
        check(remoteBackups.count == 2, "keepLatestCount=2 rotated oldest snapshot, remaining \(remoteBackups.count)")
        check(remoteBackups.map(\.fileName) == [
            "lumakey-backup-20261113-100003.lumakeybackup",
            "lumakey-backup-20261113-100002.lumakeybackup"
        ], "Remaining snapshots are newest 2 in descending order: \(remoteBackups.map(\.fileName))")

        let downloaded = try await client.downloadBackup(item: remoteBackups[0])
        check(downloaded == archiveData, "Downloaded backup matches uploaded archive byte-for-byte")
        let verifiedDownload = try BackupArchiveService.inspectBackupData(downloaded)
        check(verifiedDownload.payloadSHA256 == summary.payloadSHA256, "Downloaded archive SHA-256 verified")

        try await client.deleteBackup(item: remoteBackups[1])
        let afterDelete = try await client.listBackups()
        check(afterDelete.count == 1 && afterDelete[0].fileName == "lumakey-backup-20261113-100003.lumakeybackup", "DELETE removed target remote backup")
    }

    print("[ok] v0.7.0 BackupArchiveService (SHA-256 + Path Security + Plugins/Clipboard) & Native WebDAVClient + Keychain")
}
