import Foundation

public final class WebDAVClient: Sendable {
    public let config: WebDAVConfig
    private let password: String
    private let session: URLSession

    private static let propfindDepthZeroXML = Data("""
    <?xml version="1.0" encoding="utf-8"?>
    <d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:displayname/></d:prop></d:propfind>
    """.utf8)

    private static let propfindListXML = Data("""
    <?xml version="1.0" encoding="utf-8"?>
    <d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>
    """.utf8)

    public init(config: WebDAVConfig, password: String, sessionConfiguration: URLSessionConfiguration? = nil) {
        self.config = config
        self.password = password
        let cfg: URLSessionConfiguration
        if let custom = sessionConfiguration?.copy() as? URLSessionConfiguration {
            cfg = custom
        } else {
            cfg = .ephemeral
            cfg.timeoutIntervalForRequest = 25
            cfg.timeoutIntervalForResource = 120
        }
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    public func normalizedServerBaseURL() throws -> URL {
        let trimmed = config.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var comps = URLComponents(string: trimmed),
              let scheme = comps.scheme?.lowercased(), (scheme == "https" || scheme == "http"),
              let host = comps.host, !host.isEmpty else {
            throw WebDAVError.invalidServerURL(config.serverURL)
        }
        if comps.path.isEmpty { comps.path = "/" }
        else if !comps.path.hasSuffix("/") { comps.path += "/" }
        guard let url = comps.url else { throw WebDAVError.invalidServerURL(config.serverURL) }
        return url
    }

    public func validatedDirectorySegments() throws -> [String] {
        let raw = config.remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw == "/" { return [] }
        guard !raw.contains("\\"), !raw.contains("\0") else {
            throw WebDAVError.invalidRemotePath(config.remoteDirectory)
        }
        let segments = raw.split(separator: "/").map(String.init)
        for seg in segments where seg == "." || seg == ".." || seg.isEmpty {
            throw WebDAVError.invalidRemotePath(config.remoteDirectory)
        }
        return segments
    }

    public func remoteDirectoryURL() throws -> URL {
        var current = try normalizedServerBaseURL()
        for seg in try validatedDirectorySegments() {
            current.appendPathComponent(seg, isDirectory: true)
        }
        if !current.absoluteString.hasSuffix("/") {
            current = URL(string: current.absoluteString + "/") ?? current
        }
        return current
    }

    public func testConnection() async throws -> String {
        let baseURL = try normalizedServerBaseURL()
        let (_, resp) = try await perform(
            method: "PROPFIND",
            url: baseURL,
            headers: ["Depth": "0", "Content-Type": "application/xml; charset=utf-8"],
            body: Self.propfindDepthZeroXML
        )
        switch resp.statusCode {
        case 200, 207:
            let host = baseURL.host ?? baseURL.absoluteString
            return "WebDAV 连接与鉴权正常（HTTP \(resp.statusCode) · \(host)）"
        case 401, 403:
            throw WebDAVError.unauthorized(resp.statusCode)
        case 404:
            throw WebDAVError.notFound(baseURL.absoluteString)
        default:
            throw WebDAVError.unexpectedStatus(method: "PROPFIND", statusCode: resp.statusCode, detail: "")
        }
    }

    public func ensureRemoteDirectory() async throws {
        var current = try normalizedServerBaseURL()
        let segments = try validatedDirectorySegments()
        for seg in segments {
            current.appendPathComponent(seg, isDirectory: true)
            if !current.absoluteString.hasSuffix("/") {
                current = URL(string: current.absoluteString + "/") ?? current
            }
            let (_, resp) = try await perform(method: "MKCOL", url: current)
            switch resp.statusCode {
            case 200, 201, 204, 405:
                continue
            case 401, 403:
                throw WebDAVError.unauthorized(resp.statusCode)
            case 404, 409:
                throw WebDAVError.notFound(current.deletingLastPathComponent().absoluteString)
            default:
                throw WebDAVError.unexpectedStatus(method: "MKCOL", statusCode: resp.statusCode, detail: seg)
            }
        }
    }

    @discardableResult
    public func uploadBackup(data: Data, fileName: String? = nil) async throws -> WebDAVRemoteItem {
        try await ensureRemoteDirectory()
        let resolvedName = try sanitizeUploadFileName(fileName ?? BackupArchiveService.defaultBackupFileName())
        let dirURL = try remoteDirectoryURL()
        let targetURL = dirURL.appendingPathComponent(resolvedName, isDirectory: false)

        let (_, resp) = try await perform(
            method: "PUT",
            url: targetURL,
            headers: ["Content-Type": "application/octet-stream"],
            body: data
        )
        switch resp.statusCode {
        case 200, 201, 204:
            break
        case 401, 403:
            throw WebDAVError.unauthorized(resp.statusCode)
        case 404, 409:
            throw WebDAVError.notFound(dirURL.absoluteString)
        default:
            throw WebDAVError.unexpectedStatus(method: "PUT", statusCode: resp.statusCode, detail: resolvedName)
        }

        let listed = try await listBackups()
        let keep = max(1, config.keepLatestCount)
        if listed.count > keep {
            for stale in listed.dropFirst(keep) {
                try? await deleteBackup(item: stale)
            }
        }
        if let matched = listed.first(where: { $0.fileName == resolvedName }) {
            return matched
        }
        return WebDAVRemoteItem(
            fileName: resolvedName, href: targetURL.path, url: targetURL,
            sizeBytes: Int64(data.count), lastModified: Date()
        )
    }

    public func listBackups() async throws -> [WebDAVRemoteItem] {
        let dirURL = try remoteDirectoryURL()
        let (data, resp) = try await perform(
            method: "PROPFIND",
            url: dirURL,
            headers: ["Depth": "1", "Content-Type": "application/xml; charset=utf-8"],
            body: Self.propfindListXML
        )
        switch resp.statusCode {
        case 200, 207:
            return try WebDAVMultiStatusParser.parse(xmlData: data, baseURL: dirURL)
        case 401, 403:
            throw WebDAVError.unauthorized(resp.statusCode)
        case 404:
            throw WebDAVError.notFound(dirURL.absoluteString)
        default:
            throw WebDAVError.unexpectedStatus(method: "PROPFIND", statusCode: resp.statusCode, detail: "")
        }
    }

    public func downloadBackup(item: WebDAVRemoteItem) async throws -> Data {
        let (data, resp) = try await perform(method: "GET", url: item.url)
        switch resp.statusCode {
        case 200: return data
        case 401, 403: throw WebDAVError.unauthorized(resp.statusCode)
        case 404: throw WebDAVError.notFound(item.fileName)
        default: throw WebDAVError.unexpectedStatus(method: "GET", statusCode: resp.statusCode, detail: item.fileName)
        }
    }

    public func deleteBackup(item: WebDAVRemoteItem) async throws {
        let (_, resp) = try await perform(method: "DELETE", url: item.url)
        switch resp.statusCode {
        case 200, 202, 204: return
        case 401, 403: throw WebDAVError.unauthorized(resp.statusCode)
        case 404: throw WebDAVError.notFound(item.fileName)
        default: throw WebDAVError.unexpectedStatus(method: "DELETE", statusCode: resp.statusCode, detail: item.fileName)
        }
    }

    private func sanitizeUploadFileName(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains("\\"), !trimmed.contains("..") else {
            throw WebDAVError.invalidRemotePath(raw)
        }
        return trimmed.lowercased().hasSuffix(".\(BackupEnvelope.fileExtension)")
            ? trimmed
            : "\(trimmed).\(BackupEnvelope.fileExtension)"
    }

    private func perform(
        method: String,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        let token = Data("\(config.username):\(password)".utf8).base64EncodedString()
        req.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("Lumakey/0.7.1 (macOS; arm64)", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body

        do {
            let (data, rawResp) = try await session.data(for: req)
            guard let httpResp = rawResp as? HTTPURLResponse else {
                throw WebDAVError.networkError("服务器未返回有效的 HTTP 响应")
            }
            return (data, httpResp)
        } catch let err as WebDAVError {
            throw err
        } catch let urlErr as URLError {
            throw Self.classifyURLError(urlErr)
        } catch {
            throw WebDAVError.networkError(error.localizedDescription)
        }
    }

    private static func classifyURLError(_ err: URLError) -> WebDAVError {
        switch err.code {
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired:
            return .tlsError(err.localizedDescription)
        case .userAuthenticationRequired, .userCancelledAuthentication:
            return .unauthorized(401)
        default:
            return .networkError(err.localizedDescription)
        }
    }
}
