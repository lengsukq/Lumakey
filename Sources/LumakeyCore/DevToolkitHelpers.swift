import CoreGraphics
import CoreImage
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum DevToolkitHelpers {
    private static let rfc3986Unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func formatTimestamps(for date: Date) -> (local: String, isoUTC: String) {
        let localDF = DateFormatter()
        localDF.locale = Locale(identifier: "en_US_POSIX")
        localDF.timeZone = .current
        localDF.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let utcDF = DateFormatter()
        utcDF.locale = Locale(identifier: "en_US_POSIX")
        utcDF.timeZone = TimeZone(secondsFromGMT: 0)
        utcDF.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return (localDF.string(from: date), utcDF.string(from: date))
    }

    static func generatePassword(length: Int, includeSymbols: Bool) -> String {
        let clamped = min(max(length, 8), 128)
        let upper = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        let lower = Array("abcdefghijkmnopqrstuvwxyz")
        let digits = Array("23456789")
        let symbols = Array("!@#$%^&*-_=+")
        let pool = includeSymbols ? (upper + lower + digits + symbols) : (upper + lower + digits)

        var rng = SystemRandomNumberGenerator()
        var chars: [Character] = [
            upper.randomElement(using: &rng)!,
            lower.randomElement(using: &rng)!,
            digits.randomElement(using: &rng)!
        ]
        if includeSymbols, let sym = symbols.randomElement(using: &rng) {
            chars.append(sym)
        }
        while chars.count < clamped {
            chars.append(pool.randomElement(using: &rng)!)
        }
        chars.shuffle(using: &rng)
        return String(chars)
    }

    static func decodeBase64Flexible(_ raw: String) -> Data? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = cleaned.count % 4
        if rem > 0 { cleaned += String(repeating: "=", count: 4 - rem) }
        return Data(base64Encoded: cleaned)
    }

    static func percentEncodeRFC3986(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: rfc3986Unreserved) ?? text
    }

    static func md5Hex(_ text: String) -> String {
        Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func decodeJWT(_ token: String) -> (combinedPretty: String, payloadPretty: String, headerSummary: String)? {
        let parts = token.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let headerData = decodeBase64Flexible(String(parts[0])),
              let payloadData = decodeBase64Flexible(String(parts[1])),
              let headerObj = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let payloadObj = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else { return nil }

        let combined: [String: Any] = ["header": headerObj, "payload": payloadObj]
        guard let combData = try? JSONSerialization.data(withJSONObject: combined, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let payPrettyData = try? JSONSerialization.data(withJSONObject: payloadObj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let combText = String(data: combData, encoding: .utf8),
              let payText = String(data: payPrettyData, encoding: .utf8)
        else { return nil }

        let alg = headerObj["alg"] as? String ?? "unknown"
        var summary = "alg: \(alg)"
        if let sub = payloadObj["sub"] as? String { summary += " · sub: \(sub)" }
        if let exp = (payloadObj["exp"] as? NSNumber)?.doubleValue {
            let formatted = formatTimestamps(for: Date(timeIntervalSince1970: exp))
            summary += " · exp: \(formatted.local)"
        }
        return (combText, payText, summary)
    }

    static func parseColor(_ raw: String) -> (r: Int, g: Int, b: Int, hex: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            let hexBody = String(trimmed.dropFirst())
            if hexBody.count == 3, hexBody.allSatisfy(\.isHexDigit) {
                let chars = Array(hexBody)
                let expanded = String([chars[0], chars[0], chars[1], chars[1], chars[2], chars[2]])
                return parseColor("#" + expanded)
            }
            guard hexBody.count == 6, let val = Int(hexBody, radix: 16) else { return nil }
            let r = (val >> 16) & 0xFF, g = (val >> 8) & 0xFF, b = val & 0xFF
            return (r, g, b, String(format: "#%02X%02X%02X", r, g, b))
        }
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("rgb("), lower.hasSuffix(")") else { return nil }
        let inner = lower.dropFirst(4).dropLast()
        let comps = inner.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard comps.count == 3, comps.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return (comps[0], comps[1], comps[2], String(format: "#%02X%02X%02X", comps[0], comps[1], comps[2]))
    }

    static func rgbToHSL(r: Int, g: Int, b: Int) -> (h: Int, s: Int, l: Int) {
        let rf = Double(r) / 255.0, gf = Double(g) / 255.0, bf = Double(b) / 255.0
        let maxC = max(rf, gf, bf), minC = min(rf, gf, bf)
        let delta = maxC - minC
        let l = (maxC + minC) / 2.0
        guard delta > 0.00001 else { return (0, 0, Int((l * 100.0).rounded())) }
        let s = delta / (1.0 - abs(2.0 * l - 1.0))
        var hDeg: Double
        if maxC == rf { hDeg = 60.0 * (((gf - bf) / delta).truncatingRemainder(dividingBy: 6.0)) }
        else if maxC == gf { hDeg = 60.0 * (((bf - rf) / delta) + 2.0) }
        else { hDeg = 60.0 * (((rf - gf) / delta) + 4.0) }
        if hDeg < 0 { hDeg += 360.0 }
        return (Int(hDeg.rounded()) % 360, Int((s * 100.0).rounded()), Int((l * 100.0).rounded()))
    }

    static func renderQRCodePNG(text: String, pixelSize: Int = 360, directory: URL? = nil) -> URL? {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty,
              let filter = CIFilter(name: "CIQRCodeGenerator")
        else { return nil }
        filter.setValue(Data(content.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }

        let ciCtx = CIContext(options: [.useSoftwareRenderer: false])
        guard let rawCG = ciCtx.createCGImage(outputImage, from: outputImage.extent) else { return nil }

        let dir = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let hashPrefix = String(sha256Hex("\(pixelSize):\(content)").prefix(20))
        let outURL = dir.appendingPathComponent("qr-\(hashPrefix).png")
        if FileManager.default.fileExists(atPath: outURL.path) { return outURL }

        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pixelSize, height: pixelSize,
            bitsPerComponent: 8, bytesPerRow: pixelSize * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        ctx.interpolationQuality = .none
        let pad = CGFloat(max(16, pixelSize / 15))
        ctx.draw(rawCG, in: CGRect(x: pad, y: pad, width: CGFloat(pixelSize) - pad * 2, height: CGFloat(pixelSize) - pad * 2))

        guard let scaledCG = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, scaledCG, nil)
        return CGImageDestinationFinalize(dest) ? outURL : nil
    }
}
