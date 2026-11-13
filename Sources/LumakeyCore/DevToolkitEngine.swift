import AppKit
import Foundation

public struct DevToolResult: Identifiable, Sendable, Hashable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let copyText: String
    public let badge: String
    public let symbol: String
    public let previewImageURL: URL?
    public let colorHex: String?

    public init(
        id: String,
        title: String,
        subtitle: String,
        copyText: String,
        badge: String,
        symbol: String,
        previewImageURL: URL? = nil,
        colorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.copyText = copyText
        self.badge = badge
        self.symbol = symbol
        self.previewImageURL = previewImageURL
        self.colorHex = colorHex
    }
}

public enum DevToolkitEngine {
    public static func evaluate(_ query: String, clipboardText: String? = nil) -> [DevToolResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        let clip = clipboardText?.trimmingCharacters(in: .whitespacesAndNewlines)

        if lower == "ts" || lower == "now" {
            let now = Date()
            let sec = String(Int(now.timeIntervalSince1970))
            let ms = String(Int((now.timeIntervalSince1970 * 1000.0).rounded()))
            let fmt = DevToolkitHelpers.formatTimestamps(for: now)
            return [
                DevToolResult(id: "dev:ts:sec", title: sec, subtitle: "当前秒级时间戳 · \(fmt.local)", copyText: sec, badge: "Unix (s)", symbol: "clock.fill"),
                DevToolResult(id: "dev:ts:ms", title: ms, subtitle: "当前毫秒级时间戳 · \(fmt.isoUTC)", copyText: ms, badge: "Unix (ms)", symbol: "clock.badge.checkmark"),
                DevToolResult(id: "dev:ts:local", title: fmt.local, subtitle: "UTC: \(fmt.isoUTC)", copyText: fmt.local, badge: "本地时间", symbol: "calendar.badge.clock")
            ]
        }

        let tsCandidate = lower.hasPrefix("ts ") ? String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces) : trimmed
        if (tsCandidate.count == 10 || tsCandidate.count == 13), tsCandidate.allSatisfy(\.isNumber), let rawVal = Double(tsCandidate) {
            let seconds = tsCandidate.count == 13 ? (rawVal / 1000.0) : rawVal
            let fmt = DevToolkitHelpers.formatTimestamps(for: Date(timeIntervalSince1970: seconds))
            return [
                DevToolResult(id: "dev:ts2date:local:\(tsCandidate)", title: fmt.local, subtitle: "解析时间戳 \(tsCandidate) (本地时区)", copyText: fmt.local, badge: "本地时间", symbol: "clock.fill"),
                DevToolResult(id: "dev:ts2date:utc:\(tsCandidate)", title: fmt.isoUTC, subtitle: "解析时间戳 \(tsCandidate) (ISO8601 UTC)", copyText: fmt.isoUTC, badge: "UTC", symbol: "globe")
            ]
        }

        if lower == "uuid" || lower == "guid" {
            let raw = UUID().uuidString
            let lo = raw.lowercased()
            let compact = lo.replacingOccurrences(of: "-", with: "")
            return [
                DevToolResult(id: "dev:uuid:lo", title: lo, subtitle: "标准 v4 UUID (小写)", copyText: lo, badge: "UUID", symbol: "number.square.fill"),
                DevToolResult(id: "dev:uuid:up", title: raw.uppercased(), subtitle: "标准 v4 UUID (大写)", copyText: raw.uppercased(), badge: "UUID 大写", symbol: "textformat.abc"),
                DevToolResult(id: "dev:uuid:hex", title: compact, subtitle: "紧凑无连字符 32 位 HEX", copyText: compact, badge: "HEX32", symbol: "ellipsis.curlybraces")
            ]
        }

        if let lenArg = matchCommand(trimmed, prefixes: ["pwd", "pass"]) {
            let length = Int(lenArg) ?? 20
            let strong = DevToolkitHelpers.generatePassword(length: length, includeSymbols: true)
            let alphaNum = DevToolkitHelpers.generatePassword(length: length, includeSymbols: false)
            let clamped = min(max(length, 8), 128)
            return [
                DevToolResult(id: "dev:pwd:strong", title: strong, subtitle: "\(clamped) 位高强度随机密码（含符号）", copyText: strong, badge: "随机密码", symbol: "key.fill"),
                DevToolResult(id: "dev:pwd:alnum", title: alphaNum, subtitle: "\(clamped) 位纯字母数字密码", copyText: alphaNum, badge: "字母数字", symbol: "lock.shield.fill")
            ]
        }

        if let color = DevToolkitHelpers.parseColor(trimmed) {
            let rgbStr = "rgb(\(color.r), \(color.g), \(color.b))"
            let hsl = DevToolkitHelpers.rgbToHSL(r: color.r, g: color.g, b: color.b)
            let hslStr = "hsl(\(hsl.h), \(hsl.s)%, \(hsl.l)%)"
            let swiftUIStr = String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", Double(color.r) / 255.0, Double(color.g) / 255.0, Double(color.b) / 255.0)
            return [
                DevToolResult(id: "dev:color:hex", title: color.hex, subtitle: "\(rgbStr) · \(hslStr)", copyText: color.hex, badge: "HEX", symbol: "paintpalette.fill", colorHex: color.hex),
                DevToolResult(id: "dev:color:rgb", title: rgbStr, subtitle: "8-bit sRGB 通道值", copyText: rgbStr, badge: "RGB", symbol: "eyedropper.halffull", colorHex: color.hex),
                DevToolResult(id: "dev:color:hsl", title: hslStr, subtitle: "色相 / 饱和度 / 亮度", copyText: hslStr, badge: "HSL", symbol: "circle.lefthalf.filled", colorHex: color.hex),
                DevToolResult(id: "dev:color:swiftui", title: swiftUIStr, subtitle: "SwiftUI 原生字面量", copyText: swiftUIStr, badge: "SwiftUI", symbol: "swift", colorHex: color.hex)
            ]
        }

        return evaluateCodecsJSONAndQR(trimmed: trimmed, clip: clip)
    }

    private static func evaluateCodecsJSONAndQR(trimmed: String, clip: String?) -> [DevToolResult] {
        if let arg = matchCommand(trimmed, prefixes: ["b64"]), let src = nonEmpty(arg, fallback: clip) {
            let encoded = Data(src.utf8).base64EncodedString()
            return [DevToolResult(id: "dev:b64", title: encoded, subtitle: "Base64 编码 (\(src.count) 字符)", copyText: encoded, badge: "Base64", symbol: "arrow.left.arrow.right.square")]
        }
        if let arg = matchCommand(trimmed, prefixes: ["b64d"]), let src = nonEmpty(arg, fallback: clip) {
            guard let data = DevToolkitHelpers.decodeBase64Flexible(src), let decoded = String(data: data, encoding: .utf8) else {
                return [DevToolResult(id: "dev:b64d:err", title: "Base64 解码失败", subtitle: "输入不是合法的 UTF-8 Base64 字符串", copyText: src, badge: "解码错误", symbol: "exclamationmark.triangle")]
            }
            return [DevToolResult(id: "dev:b64d", title: decoded, subtitle: "Base64 解码结果", copyText: decoded, badge: "Base64 解码", symbol: "lock.open.fill")]
        }
        if let arg = matchCommand(trimmed, prefixes: ["url"]), let src = nonEmpty(arg, fallback: clip) {
            let enc = DevToolkitHelpers.percentEncodeRFC3986(src)
            return [DevToolResult(id: "dev:url", title: enc, subtitle: "URL RFC3986 百分号编码", copyText: enc, badge: "URL 编码", symbol: "link")]
        }
        if let arg = matchCommand(trimmed, prefixes: ["urld"]), let src = nonEmpty(arg, fallback: clip) {
            let dec = src.removingPercentEncoding ?? src
            return [DevToolResult(id: "dev:urld", title: dec, subtitle: "URL 百分号解码", copyText: dec, badge: "URL 解码", symbol: "link.badge.plus")]
        }
        if let arg = matchCommand(trimmed, prefixes: ["md5"]), let src = nonEmpty(arg, fallback: clip) {
            let hex = DevToolkitHelpers.md5Hex(src)
            return [DevToolResult(id: "dev:md5", title: hex, subtitle: "MD5 (32 位小写)", copyText: hex, badge: "MD5", symbol: "number")]
        }
        if let arg = matchCommand(trimmed, prefixes: ["sha256"]), let src = nonEmpty(arg, fallback: clip) {
            let hex = DevToolkitHelpers.sha256Hex(src)
            return [DevToolResult(id: "dev:sha256", title: hex, subtitle: "SHA-256 (CryptoKit)", copyText: hex, badge: "SHA256", symbol: "checkmark.shield.fill")]
        }
        if let arg = matchCommand(trimmed, prefixes: ["jwt"]), let src = nonEmpty(arg, fallback: clip) {
            guard let jwt = DevToolkitHelpers.decodeJWT(src) else {
                return [DevToolResult(id: "dev:jwt:err", title: "JWT 解析失败", subtitle: "需要形如 header.payload.signature 的合法 Token", copyText: src, badge: "JWT 错误", symbol: "exclamationmark.triangle")]
            }
            return [
                DevToolResult(id: "dev:jwt:all", title: jwt.headerSummary, subtitle: "免验签解码 Header & Payload 美化 JSON", copyText: jwt.combinedPretty, badge: "JWT", symbol: "person.badge.key.fill"),
                DevToolResult(id: "dev:jwt:payload", title: firstLinePreview(jwt.payloadPretty), subtitle: "仅复制 JWT Payload JSON", copyText: jwt.payloadPretty, badge: "Payload", symbol: "doc.plaintext")
            ]
        }
        if let arg = matchCommand(trimmed, prefixes: ["json"]) {
            let isExplicit = !arg.isEmpty
            guard let src = nonEmpty(arg, fallback: clip) else { return [] }
            let looksLikeJSON = src.hasPrefix("{") || src.hasPrefix("[")
            guard isExplicit || looksLikeJSON else { return [] }
            do {
                let obj = try JSONSerialization.jsonObject(with: Data(src.utf8), options: [])
                let prettyData = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                let miniData = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])
                let pretty = String(data: prettyData, encoding: .utf8) ?? src
                let mini = String(data: miniData, encoding: .utf8) ?? src
                return [
                    DevToolResult(id: "dev:json:pretty", title: "JSON 校验通过 · 美化缩进", subtitle: "\(pretty.components(separatedBy: .newlines).count) 行 · 点击复制美化 JSON", copyText: pretty, badge: "JSON 美化", symbol: "curlybraces"),
                    DevToolResult(id: "dev:json:mini", title: firstLinePreview(mini), subtitle: "单行压缩 Minified JSON (\(mini.count) 字节)", copyText: mini, badge: "JSON 压缩", symbol: "arrow.down.right.and.arrow.up.left")
                ]
            } catch {
                return [DevToolResult(id: "dev:json:err", title: "JSON 语法校验未通过", subtitle: error.localizedDescription, copyText: src, badge: "JSON 错误", symbol: "exclamationmark.triangle.fill")]
            }
        }
        if let arg = matchCommand(trimmed, prefixes: ["qr"]), let src = nonEmpty(arg, fallback: clip),
           let pngURL = generateQRCodePNG(for: src) {
            return [
                DevToolResult(
                    id: "dev:qr:\(pngURL.lastPathComponent)",
                    title: "二维码已生成 (\(firstLinePreview(src)))",
                    subtitle: "360×360 无锯齿高清 PNG · 支持复制图片或钉在桌面",
                    copyText: src, badge: "QR 码", symbol: "qrcode", previewImageURL: pngURL
                )
            ]
        }
        return []
    }

    public static func generateQRCodePNG(for text: String, pixelSize: Int = 360, directory: URL? = nil) -> URL? {
        DevToolkitHelpers.renderQRCodePNG(text: text, pixelSize: pixelSize, directory: directory)
    }

    @MainActor
    @discardableResult
    public static func copyQRImageToPasteboard(at url: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        ScreenshotCompositor.copyImageFileToPasteboard(at: url, to: pasteboard)
    }

    private static func matchCommand(_ raw: String, prefixes: [String]) -> String? {
        let lower = raw.lowercased()
        for p in prefixes {
            if lower == p { return "" }
            if lower.hasPrefix(p + " ") {
                return String(raw.dropFirst(p.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func nonEmpty(_ primary: String, fallback: String?) -> String? {
        if !primary.isEmpty { return primary }
        if let f = fallback, !f.isEmpty { return f }
        return nil
    }

    private static func firstLinePreview(_ text: String) -> String {
        let single = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return single.count > 56 ? String(single.prefix(56)) + "…" : single
    }
}
