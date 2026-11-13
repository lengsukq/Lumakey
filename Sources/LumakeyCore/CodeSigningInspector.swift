import Foundation
import Security

public enum CodeSignatureMode: Sendable, Equatable {
    case certificate(commonName: String)
    case adHoc
    case unsigned
}

public struct CodeSigningStatus: Sendable, Equatable {
    public let mode: CodeSignatureMode
    public let bundleIdentifier: String
    public let isStableForTCC: Bool
    public let badgeTitle: String
    public let explanation: String

    public init(
        mode: CodeSignatureMode,
        bundleIdentifier: String,
        isStableForTCC: Bool,
        badgeTitle: String,
        explanation: String
    ) {
        self.mode = mode
        self.bundleIdentifier = bundleIdentifier
        self.isStableForTCC = isStableForTCC
        self.badgeTitle = badgeTitle
        self.explanation = explanation
    }
}

public enum CodeSigningInspector {
    public static func inspect(bundleURL: URL = Bundle.main.bundleURL) -> CodeSigningStatus {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return CodeSigningStatus(
                mode: .unsigned,
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "app.lumakey.macos",
                isStableForTCC: false,
                badgeTitle: "未检测到有效代码签名",
                explanation: "当前处于未签名构建环境，重装后系统会要求重新授权。"
            )
        }

        var rawInfo: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        let infoStatus = SecCodeCopySigningInformation(staticCode, flags, &rawInfo)
        guard infoStatus == errSecSuccess, let info = rawInfo as? [String: Any] else {
            return CodeSigningStatus(
                mode: .unsigned,
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "app.lumakey.macos",
                isStableForTCC: false,
                badgeTitle: "未签名状态",
                explanation: "未能读取签名信息，建议运行签名初始化脚本。"
            )
        }

        let identifier = (info[kSecCodeInfoIdentifier as String] as? String)
            ?? (Bundle.main.bundleIdentifier ?? "app.lumakey.macos")
        let codeFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let isAdHoc = (codeFlags & 0x0002) != 0

        if !isAdHoc,
           let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let leaf = certs.first {
            var commonName: CFString?
            SecCertificateCopyCommonName(leaf, &commonName)
            let cn = (commonName as String?) ?? "本地受信任证书"
            return CodeSigningStatus(
                mode: .certificate(commonName: cn),
                bundleIdentifier: identifier,
                isStableForTCC: true,
                badgeTitle: "稳定证书签名 (\(cn)) · 升级免重授权",
                explanation: "已通过固定身份证书签署 \(identifier)，每次构建更新均可保留「辅助功能」与「屏幕录制」授权。"
            )
        }

        return CodeSigningStatus(
            mode: .adHoc,
            bundleIdentifier: identifier,
            isStableForTCC: false,
            badgeTitle: "临时 Ad-hoc 签名 · 重装后需重新授权",
            explanation: "当前未检测到钥匙串代码签名证书，macOS TCC 会把权限绑定到单次构建哈希；在终端执行一次 setup-local-signing.sh 即可永久固定。"
        )
    }
}
