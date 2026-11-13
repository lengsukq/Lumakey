import Foundation

public struct UserFacingDiagnostic: Sendable, Hashable {
    public let title: String
    public let reason: String
    public let dataSafety: String
    public let nextStep: String

    public init(title: String, reason: String, dataSafety: String, nextStep: String) {
        self.title = title
        self.reason = reason
        self.dataSafety = dataSafety
        self.nextStep = nextStep
    }
}

public enum LumakeyError: Error, Sendable {
    case directoryNotFound(URL)
    case directoryUnreadable(URL, String)
    case readOnlyVolume(String)
    case invalidRenameTarget(String)
    case renameConflict(String)
    case fileOperationBlocked(title: String, reason: String, nextStep: String)
    case visionFailed(String)
    case screenshotCancelled
    case pluginInvalid(String)
    case pluginExecutionFailed(String)

    public var diagnostic: UserFacingDiagnostic {
        switch self {
        case .directoryNotFound(let url):
            return UserFacingDiagnostic(
                title: "找不到目录",
                reason: "路径不存在或外置设备已断开：\(url.path)",
                dataSafety: "原有文件未发生任何改动。",
                nextStep: "请确认外置硬盘连接正常后切换其他位置。"
            )
        case .directoryUnreadable(let url, let detail):
            return UserFacingDiagnostic(
                title: "无法读取目录",
                reason: "系统拒绝访问 \(url.lastPathComponent)：\(detail)",
                dataSafety: "未写入或修改任何数据。",
                nextStep: "请在系统设置 -> 隐私与安全性 -> 完全磁盘访问权限 中授权 Lumakey。"
            )
        case .readOnlyVolume(let volumeName):
            return UserFacingDiagnostic(
                title: "磁盘当前为只读状态",
                reason: "卷“\(volumeName)”挂载为只读（常见于 macOS 原生 NTFS 只读驱动）。",
                dataSafety: "所有写操作已安全拦截，不会损坏分区结构。",
                nextStep: "仅执行查看/播放，或在 Windows 安全弹出后使用受信任的 NTFS-3G 方案挂载。"
            )
        case .invalidRenameTarget(let detail):
            return UserFacingDiagnostic(
                title: "重命名目标不合法",
                reason: detail,
                dataSafety: "批处理已全部取消，未重命名任何文件。",
                nextStep: "移除名称中的“/”或“:”并确保目标名非空。"
            )
        case .renameConflict(let detail):
            return UserFacingDiagnostic(
                title: "存在目标文件名冲突",
                reason: detail,
                dataSafety: "已拦截提交，原文件名保持不变。",
                nextStep: "调整前缀、后缀或替换规则以消除重复名称。"
            )
        case .fileOperationBlocked(let title, let reason, let nextStep):
            return UserFacingDiagnostic(
                title: title,
                reason: reason,
                dataSafety: "操作已安全中止，未破坏或覆盖任何现有文件。",
                nextStep: nextStep
            )
        case .visionFailed(let detail):
            return UserFacingDiagnostic(
                title: "系统视觉识别未完成",
                reason: detail,
                dataSafety: "原始图片与剪贴板数据未被破坏。",
                nextStep: "换一张包含清晰主体或文字的图片再试。"
            )
        case .screenshotCancelled:
            return UserFacingDiagnostic(
                title: "已取消选区截图",
                reason: "用户在系统截图选区中按下 Esc 或未完成框选。",
                dataSafety: "未生成临时截图文件。",
                nextStep: "随时重新点击“截图”发起新的框选。"
            )
        case .pluginInvalid(let detail):
            return UserFacingDiagnostic(
                title: "插件清单或路径无效",
                reason: detail,
                dataSafety: "未执行任何未受信任插件脚本。",
                nextStep: "修正 plugin.json 字段或使用 MCP 校验工具检查。"
            )
        case .pluginExecutionFailed(let detail):
            return UserFacingDiagnostic(
                title: "插件执行失败",
                reason: detail,
                dataSafety: "插件进程已结束，工作区文件未受直接更改。",
                nextStep: "检查插件入口脚本权限与标准错误输出。"
            )
        }
    }
}
