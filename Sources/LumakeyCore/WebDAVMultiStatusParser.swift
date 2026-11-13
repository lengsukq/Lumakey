import Foundation

public enum WebDAVError: Error, LocalizedError, Sendable, Equatable {
    case invalidServerURL(String)
    case invalidRemotePath(String)
    case unauthorized(Int)
    case notFound(String)
    case tlsError(String)
    case networkError(String)
    case unexpectedStatus(method: String, statusCode: Int, detail: String)
    case xmlParseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL(let raw):
            "WebDAV 服务器地址无效：\(raw)（需以 https:// 或 http:// 开头）"
        case .invalidRemotePath(let path):
            "远端目录或文件名不合法：\(path)"
        case .unauthorized(let code):
            "WebDAV 账号或密码鉴权失败（HTTP \(code)），请核对用户名及应用专用密码"
        case .notFound(let target):
            "WebDAV 远端路径不存在（HTTP 404）：\(target)"
        case .tlsError(let detail):
            "TLS 安全证书或加密握手失败：\(detail)"
        case .networkError(let detail):
            "无法连接 WebDAV 服务器：\(detail)"
        case .unexpectedStatus(let method, let code, let detail):
            detail.isEmpty
                ? "WebDAV \(method) 请求返回异常状态（HTTP \(code)）"
                : "WebDAV \(method) 失败（HTTP \(code)）：\(detail)"
        case .xmlParseFailed(let detail):
            "解析 WebDAV 207 Multi-Status XML 失败：\(detail)"
        }
    }
}

public struct WebDAVRemoteItem: Identifiable, Sendable, Equatable, Hashable {
    public var id: String { url.absoluteString }
    public let fileName: String
    public let href: String
    public let url: URL
    public let sizeBytes: Int64
    public let lastModified: Date?

    public init(fileName: String, href: String, url: URL, sizeBytes: Int64, lastModified: Date?) {
        self.fileName = fileName
        self.href = href
        self.url = url
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
    }

    public var sortDate: Date {
        lastModified ?? WebDAVMultiStatusParser.parseFilenameTimestamp(fileName) ?? .distantPast
    }
}

public enum WebDAVMultiStatusParser {
    public static func parse(xmlData: Data, baseURL: URL) throws -> [WebDAVRemoteItem] {
        let delegate = MultiStatusXMLDelegate(baseURL: baseURL)
        let parser = XMLParser(data: xmlData)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            let reason = parser.parserError?.localizedDescription ?? "未知 XML 语法错误"
            throw WebDAVError.xmlParseFailed(reason)
        }
        var seen = Set<String>()
        let unique = delegate.items.filter { seen.insert($0.url.absoluteString).inserted }
        return unique.sorted { lhs, rhs in
            if lhs.sortDate != rhs.sortDate { return lhs.sortDate > rhs.sortDate }
            return lhs.fileName > rhs.fileName
        }
    }

    public static func parseHTTPDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEEE, dd-MMM-yy HH:mm:ss zzz",
            "EEE MMM d HH:mm:ss yyyy"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for fmt in formats {
            df.dateFormat = fmt
            if let date = df.date(from: trimmed) { return date }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    public static func parseFilenameTimestamp(_ fileName: String) -> Date? {
        let lower = fileName.lowercased()
        guard lower.hasPrefix("lumakey-backup-"), lower.count >= 30 else { return nil }
        let stamp = String(fileName.dropFirst("lumakey-backup-".count).prefix(15))
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMdd-HHmmss"
        return df.date(from: stamp)
    }

    static func resolveHrefURL(_ rawHref: String, baseURL: URL) -> URL? {
        let href = rawHref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !href.isEmpty else { return nil }
        if href.lowercased().hasPrefix("http://") || href.lowercased().hasPrefix("https://") {
            if let direct = URL(string: href) { return direct }
            return href.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
        }
        if href.hasPrefix("/") {
            var comps = URLComponents()
            comps.scheme = baseURL.scheme
            comps.host = baseURL.host
            comps.port = baseURL.port
            comps.percentEncodedPath = href
            if let url = comps.url { return url }
            var fallback = URLComponents()
            fallback.scheme = baseURL.scheme
            fallback.host = baseURL.host
            fallback.port = baseURL.port
            fallback.path = href
            return fallback.url
        }
        return URL(string: href, relativeTo: baseURL)?.absoluteURL
    }
}

private final class MultiStatusXMLDelegate: NSObject, XMLParserDelegate {
    private enum ActiveField { case href, contentLength, lastModified }

    let baseURL: URL
    var items: [WebDAVRemoteItem] = []

    private var inResponse = false
    private var inProp = false
    private var inResourceType = false
    private var activeField: ActiveField?
    private var hrefText = ""
    private var lengthText = ""
    private var modifiedText = ""
    private var isCollection = false

    init(baseURL: URL) { self.baseURL = baseURL }

    private func localName(_ elementName: String) -> String {
        (elementName.split(separator: ":").last.map(String.init) ?? elementName).lowercased()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let tag = localName(elementName)
        if tag == "response" {
            inResponse = true; inProp = false; inResourceType = false; activeField = nil
            hrefText = ""; lengthText = ""; modifiedText = ""; isCollection = false
            return
        }
        guard inResponse else { return }
        switch tag {
        case "prop": inProp = true
        case "resourcetype": inResourceType = true
        case "collection" where inResourceType: isCollection = true
        case "href" where !inProp && hrefText.isEmpty: activeField = .href
        case "getcontentlength" where inProp && lengthText.isEmpty: activeField = .contentLength
        case "getlastmodified" where inProp && modifiedText.isEmpty: activeField = .lastModified
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let activeField else { return }
        switch activeField {
        case .href: hrefText += string
        case .contentLength: lengthText += string
        case .lastModified: modifiedText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let tag = localName(elementName)
        switch tag {
        case "href", "getcontentlength", "getlastmodified":
            activeField = nil
        case "resourcetype":
            inResourceType = false
        case "prop":
            inProp = false
        case "response":
            finalizeResponse()
            inResponse = false
        default:
            break
        }
    }

    private func finalizeResponse() {
        let trimmedHref = hrefText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isCollection, !trimmedHref.isEmpty, !trimmedHref.hasSuffix("/"),
              let url = WebDAVMultiStatusParser.resolveHrefURL(trimmedHref, baseURL: baseURL) else { return }
        let rawLast = url.lastPathComponent
        let fileName = rawLast.removingPercentEncoding ?? rawLast
        guard fileName.lowercased().hasSuffix(".\(BackupEnvelope.fileExtension)") else { return }
        let size = Int64(lengthText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let modDate = WebDAVMultiStatusParser.parseHTTPDate(modifiedText)
        items.append(WebDAVRemoteItem(fileName: fileName, href: trimmedHref, url: url, sizeBytes: size, lastModified: modDate))
    }
}
