import Foundation
import Security

public struct WebDAVConfig: Codable, Sendable, Equatable {
    public static let configFileName = "webdav-config.json"

    public var serverURL: String
    public var username: String
    public var remoteDirectory: String
    public var keepLatestCount: Int
    public var autoBackupOnLaunch: Bool

    enum CodingKeys: String, CodingKey {
        case serverURL
        case username
        case remoteDirectory
        case keepLatestCount
        case autoBackupOnLaunch
    }

    public init(
        serverURL: String = "",
        username: String = "",
        remoteDirectory: String = "LumakeyBackups",
        keepLatestCount: Int = 10,
        autoBackupOnLaunch: Bool = false
    ) {
        self.serverURL = serverURL
        self.username = username
        self.remoteDirectory = remoteDirectory
        self.keepLatestCount = max(1, keepLatestCount)
        self.autoBackupOnLaunch = autoBackupOnLaunch
    }

    public var isConfigured: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func defaultConfigURL(
        in appSupportDirectory: URL = BackupArchiveService.defaultAppSupportDirectory()
    ) -> URL {
        appSupportDirectory.appendingPathComponent(configFileName, isDirectory: false)
    }

    public static func load(from url: URL = defaultConfigURL()) -> WebDAVConfig {
        guard let data = try? Data(contentsOf: url),
              var decoded = try? JSONDecoder().decode(WebDAVConfig.self, from: data) else {
            return WebDAVConfig()
        }
        decoded.keepLatestCount = max(1, decoded.keepLatestCount)
        if decoded.remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            decoded.remoteDirectory = "LumakeyBackups"
        }
        return decoded
    }

    public func save(to url: URL = defaultConfigURL()) {
        var normalized = self
        normalized.keepLatestCount = max(1, normalized.keepLatestCount)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(normalized) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

public struct WebDAVProviderPreset: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let sampleURL: String
    public let setupHint: String
    public let symbol: String

    public static let allPresets: [WebDAVProviderPreset] = [
        WebDAVProviderPreset(
            id: "jianguoyun",
            name: "坚果云",
            sampleURL: "https://dav.jianguoyun.com/dav/",
            setupHint: "坚果云基础路径必须包含 /dav/，并在网页端「账户信息 -> 安全选项」生成第三方应用专用密码。",
            symbol: "icloud.fill"
        ),
        WebDAVProviderPreset(
            id: "nextcloud",
            name: "Nextcloud",
            sampleURL: "https://cloud.example.com/remote.php/dav/files/username/",
            setupHint: "Nextcloud 路径末尾替换为您自己的登录用户名，推荐使用「安全 -> 设备与会话」应用密码。",
            symbol: "cloud.fill"
        ),
        WebDAVProviderPreset(
            id: "synology",
            name: "Synology / NAS",
            sampleURL: "https://nas.example.com:5006/",
            setupHint: "群晖 / 绿联 / LightIsle NAS 开启 WebDAV Server 后默认 HTTPS 端口 5006（HTTP 为 5005）。",
            symbol: "externaldrive.connected.to.line.below.fill"
        ),
        WebDAVProviderPreset(
            id: "alist",
            name: "Alist / OpenList",
            sampleURL: "https://alist.example.com/dav/",
            setupHint: "Alist 与 OpenList 统一挂载 WebDAV 入口为 /dav/，账号需开启 WebDAV 读取与管理写入权限。",
            symbol: "server.rack"
        )
    ]
}

public enum WebDAVKeychainError: Error, LocalizedError, Sendable, Equatable {
    case unhandledStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            let msg = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
            return "系统钥匙串访问失败：\(msg)"
        }
    }
}

public enum WebDAVKeychainStore {
    public static let defaultService = "app.lumakey.macos.webdav"

    private static func normalizedAccount(_ account: String) -> String {
        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "default" : trimmed
    }

    public static func savePassword(
        _ password: String,
        account: String,
        service: String = defaultService
    ) throws {
        if password.isEmpty {
            try deletePassword(account: account, service: service)
            return
        }
        let acct = normalizedAccount(account)
        let secretData = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct
        ]
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: secretData
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw WebDAVKeychainError.unhandledStatus(updateStatus)
        }

        var insertQuery = query
        insertQuery[kSecValueData as String] = secretData
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        insertQuery[kSecAttrLabel as String] = "Lumakey WebDAV (\(acct))"
        let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw WebDAVKeychainError.unhandledStatus(addStatus)
        }
    }

    public static func loadPassword(
        account: String,
        service: String = defaultService
    ) throws -> String? {
        let acct = normalizedAccount(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw WebDAVKeychainError.unhandledStatus(status)
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func deletePassword(
        account: String,
        service: String = defaultService
    ) throws {
        let acct = normalizedAccount(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WebDAVKeychainError.unhandledStatus(status)
        }
    }
}
