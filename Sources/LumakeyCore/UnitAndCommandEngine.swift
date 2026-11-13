import Foundation

public struct UnitConversionResult: Sendable, Hashable {
    public let expression: String
    public let resultText: String
    public let badgeLabel: String
}

public enum SystemCommandKind: Sendable, Hashable {
    case openWelcome
    case openWorkspace
    case openSettings
    case openClipboard
    case openEverything
    case capturePin
    case captureOCR
    case recordGif
    case openTrash
    case emptyTrash
    case lockScreen
    case toggleMosEnabled
    case toggleMosReverse
    case toggleMosSmooth
    case openMosSettings
    case toggleSystemMonitor
    case openNetworkMonitor
    case openCacheManager
    case openBackupSettings
    case quickBackup
    case openSnippetsSettings
    case openPluginsSettings
    case reclaimMemory
    case inspectPort(Int)
    case openVolume(URL)
    case webSearch(engine: String, url: URL)
}

public struct CommandSuggestion: Identifiable, Sendable, Hashable {
    public let id: String
    public let score: Int
    public let title: String
    public let subtitle: String
    public let badgeLabel: String
    public let symbol: String
    public let command: SystemCommandKind
}

public enum UnitAndCommandEngine {
    public static func evaluate(_ raw: String) -> UnitConversionResult? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let base = evaluateBaseConversion(trimmed) { return base }
        return evaluateUnitConversion(trimmed)
    }

    public static func matchCommands(query: String, volumes: [VolumeSummary]) -> [CommandSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.isEmpty {
            return [
                CommandSuggestion(id: "cmd:welcome", score: 420, title: "欢迎使用 流光 Lumakey", subtitle: "查看全部快捷能力与全局热键指南", badgeLabel: "引导", symbol: "sparkles", command: .openWelcome),
                CommandSuggestion(id: "cmd:everything", score: 410, title: "Everything 全盘秒搜 (⌥F)", subtitle: "紧凑索引支持 ext: / video: / pic: / path:", badgeLabel: "秒搜", symbol: "magnifyingglass", command: .openEverything),
                CommandSuggestion(id: "cmd:clipboard", score: 400, title: "剪贴板历史 (⌥C)", subtitle: "自动记录文本、颜色色值、图片与文件路径", badgeLabel: "剪贴板", symbol: "doc.on.clipboard", command: .openClipboard),
                CommandSuggestion(id: "cmd:capture-pin", score: 390, title: "选区截图钉屏 (⌥A)", subtitle: "调用系统截图并悬浮置顶，悬停可 OCR/抠图", badgeLabel: "截图", symbol: "camera.viewfinder", command: .capturePin),
                CommandSuggestion(id: "cmd:workspace", score: 380, title: "双栏文件与外置 NTFS 工作台 · 附加 (⌥E)", subtitle: "侧边实时预览、只读看图/播片、NTFS 安全识别", badgeLabel: "附加", symbol: "folder.fill", command: .openWorkspace)
            ]
        }

        var items: [CommandSuggestion] = []
        if lower.hasPrefix("port ") {
            let arg = lower.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if let port = Int(arg), (1...65_535).contains(port) {
                items.append(CommandSuggestion(id: "cmd:port:\(port)", score: 9_600, title: "查看端口 \(port) 监听进程", subtitle: "调用系统 lsof 检测占用进程", badgeLabel: "端口", symbol: "network", command: .inspectPort(port)))
            }
        }

        let webPrefixes: [(prefix: String, name: String, baseURL: String)] = [
            ("g ", "Google", "https://www.google.com/search?q="),
            ("gh ", "GitHub", "https://github.com/search?q="),
            ("bd ", "百度", "https://www.baidu.com/s?wd="),
            ("bili ", "哔哩哔哩", "https://search.bilibili.com/all?keyword=")
        ]
        for engine in webPrefixes where lower.hasPrefix(engine.prefix) {
            let term = String(trimmed.dropFirst(engine.prefix.count)).trimmingCharacters(in: .whitespaces)
            if let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: engine.baseURL + encoded), !term.isEmpty {
                items.append(CommandSuggestion(id: "cmd:web:\(engine.name)", score: 9_400, title: "用 \(engine.name) 搜索「\(term)」", subtitle: "在默认浏览器打开搜索结果", badgeLabel: "网页", symbol: "globe", command: .webSearch(engine: engine.name, url: url)))
            }
        }

        let diskKeywords = ["ntfs", "disk", "volumes", "磁盘", "外置", "硬盘"]
        if lower.count >= 2 && diskKeywords.contains(where: { $0.hasPrefix(lower) || lower.contains($0) }) {
            for vol in volumes where vol.mountPath != "/" {
                let url = URL(fileURLWithPath: vol.mountPath)
                items.append(CommandSuggestion(id: "cmd:vol:\(vol.mountPath)", score: 8_800, title: "打开磁盘 \(vol.name)", subtitle: "\(vol.mountPath) · \(vol.capacityText)", badgeLabel: vol.formatKind.badgeText, symbol: "externaldrive.fill", command: .openVolume(url)))
            }
        }

        let catalog: [(keywords: [String], id: String, title: String, subtitle: String, badge: String, symbol: String, cmd: SystemCommandKind)] = [
            (["lock", "锁屏", "suoping"], "lock", "锁定屏幕", "立即锁定当前 macOS 会话", "系统", "lock.fill", .lockScreen),
            (["trash", "废纸篓", "feizhilou"], "trash", "打开废纸篓", "在访达中查看废纸篓内容", "系统", "trash", .openTrash),
            (["emptytrash", "清空废纸篓"], "emptytrash", "清空废纸篓", "通过系统访达执行清空（需确认）", "系统", "trash.slash.fill", .emptyTrash),
            (["ocr", "识字", "shizi"], "ocr", "截图并离线 OCR 识字 (⌥O)", "调用 Vision 中英识别并复制", "视觉", "text.viewfinder", .captureOCR),
            (["screenshot", "截图", "jietu", "钉图"], "capture", "选区截图并钉在屏幕 (⌥A)", "悬停工具条支持识别与主体抠图", "截图", "camera.viewfinder", .capturePin),
            (["gif", "录屏", "动图", "record", "luping", "dongtu"], "gif-record", "区域 / 窗口 GIF 动图录制 (⌥G)", "框选区域或吸附窗口录制高帧率轻量 GIF 并复制", "录屏", "record.circle.fill", .recordGif),
            (["clipboard", "剪贴板", "jianqieban"], "clip", "打开剪贴板历史 (⌥C)", "按类型筛选并回车复制", "工具", "doc.on.clipboard.fill", .openClipboard),
            (["files", "workspace", "工作台", "gongzuotai"], "ws", "打开双栏文件工作台 (⌥E)", "外置 NTFS 检测与侧边预览", "附加", "sidebar.squares.left", .openWorkspace),
            (["settings", "设置", "shezhi"], "settings", "流光设置与插件中心 (⌘,)", "外观、索引目录、MCP 与快捷键", "设置", "gearshape.fill", .openSettings),
            (["备份", "backup", "webdav", "导出", "云同步", "beifen"], "backup-settings", "打开导出、备份与 WebDAV 云同步", "导出 .lumakeybackup 归档或同步至坚果云 / Nextcloud / NAS", "备份", "externaldrive.badge.icloud", .openBackupSettings),
            (["快速备份", "立即备份", "quick backup"], "quick-backup", "立即执行快速备份快照", "已配置 WebDAV 时后台上传云快照，否则导出本地归档", "备份", "icloud.and.arrow.up.fill", .quickBackup),
            (["短语", "snippets", "snippet", "快捷短语", "duanyu"], "snippets-settings", "管理快捷短语词库 (Snippets)", "配置 ;date / ;sh / ;uuid / ;clip 等动态展开模板", "短语", "text.quote", .openSnippetsSettings),
            (["插件", "plugins", "plugin", "mcp"], "plugins-settings", "打开插件市场与 MCP 扩展中心", "安装精选原生插件、参数配置与 FSEvents 热重载", "插件", "puzzlepiece.extension.fill", .openPluginsSettings),
            (["mos", "mouse", "鼠标", "滚轮", "平滑", "shubiao", "gunlun"], "mos-toggle", "切换 Mos 鼠标平滑与滚轮方向", "开启/关闭物理鼠标独立滚轮优化", "Mos", "computermouse.fill", .toggleMosEnabled),
            (["mos reverse", "反转滚轮", "鼠标反转"], "mos-rev", "切换物理鼠标滚轮反转", "仅作用于外接鼠标，保留触控板自然滚动", "Mos", "arrow.up.arrow.down", .toggleMosReverse),
            (["mos smooth", "平滑滚动"], "mos-smooth", "切换 Mos 120Hz 平滑滚动", "为物理鼠标滚轮启用高帧率像素插值", "Mos", "waveform.path", .toggleMosSmooth),
            (["mos settings", "鼠标设置"], "mos-settings", "打开 Mos 鼠标插件设置", "配置步长、平滑度、辅助权限与应用排除", "Mos", "slider.horizontal.3", .openMosSettings),
            (["monitor", "cpu", "ram", "net", "power", "监控", "系统监控", "网速", "功耗", "频率", "脉搏"], "sys-monitor", "切换系统脉搏监控悬浮窗 (⌥M)", "实时查看 CPU 频率、内存、功耗、网速，支持贴边隐藏与顶部精简展开", "监控", "waveform.path.ecg", .toggleSystemMonitor),
            (["network", "traffic", "nettop", "流量", "网络监控", "去向", "连接", "wangluo"], "net-monitor", "打开本机网络流量与去向监控 (⌥N)", "实时查看每个应用的上下行网速、远端 IP 域名与连接状态", "流量", "network", .openNetworkMonitor),
            (["cache", "clean", "storage", "缓存", "清理缓存", "应用缓存", "huancun"], "app-cache", "打开本应用缓存与存储管理", "查看并一键清理剪贴板、截图钉屏、抠图与影院转封装缓存", "缓存", "internaldrive.fill", .openCacheManager),
            (["memory", "mem", "内存", "释放内存", "gc"], "reclaim-mem", "立即释放空闲内存与子进程", "卸载空闲索引并回收可释放堆内存页", "内存", "memorychip", .reclaimMemory),
            (["welcome", "引导", "help"], "welcome", "打开欢迎引导页", "查看全部快捷能力概览", "引导", "sparkles", .openWelcome)
        ]
        for item in catalog {
            let exact = item.keywords.contains(lower)
            let prefix = lower.count >= 2 && item.keywords.contains(where: { $0.hasPrefix(lower) || lower.hasPrefix($0) })
            if exact || prefix {
                items.append(CommandSuggestion(id: "cmd:\(item.id)", score: exact ? 8_600 : 7_200, title: item.title, subtitle: item.subtitle, badgeLabel: item.badge, symbol: item.symbol, command: item.cmd))
            }
        }
        return items
    }

    public static func inspectListeningPort(_ port: Int) -> String {
        guard let result = try? ProcessSupervisor.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"],
            timeoutSeconds: 3.0,
            maxOutputBytes: 32_768
        ) else {
            return "无法运行系统 lsof。"
        }
        if result.timedOut {
            return "lsof 查询端口 \(port) 超时并已被自动终止。"
        }
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? "端口 \(port) 当前无监听进程。" : out
    }

    private static func evaluateBaseConversion(_ trimmed: String) -> UnitConversionResult? {
        let normalized = trimmed.lowercased()
            .replacingOccurrences(of: " 转 ", with: " to ")
            .replacingOccurrences(of: " in ", with: " to ")
        let parts = normalized.components(separatedBy: " to ")
        guard parts.count == 2 else { return nil }
        let lhs = parts[0].trimmingCharacters(in: .whitespaces)
        let target = parts[1].trimmingCharacters(in: .whitespaces)
        let number: Int64? = lhs.hasPrefix("0x") ? Int64(lhs.dropFirst(2), radix: 16) : Int64(lhs)
        guard let number else { return nil }
        switch target {
        case "hex", "16": return UnitConversionResult(expression: trimmed, resultText: "0x" + String(number, radix: 16, uppercase: true), badgeLabel: "进制")
        case "bin", "2": return UnitConversionResult(expression: trimmed, resultText: "0b" + String(number, radix: 2), badgeLabel: "进制")
        case "oct", "8": return UnitConversionResult(expression: trimmed, resultText: "0o" + String(number, radix: 8), badgeLabel: "进制")
        case "dec", "10": return UnitConversionResult(expression: trimmed, resultText: String(number), badgeLabel: "进制")
        default: return nil
        }
    }

    private static func evaluateUnitConversion(_ trimmed: String) -> UnitConversionResult? {
        let normalized = trimmed.lowercased()
            .replacingOccurrences(of: " 转 ", with: " to ")
            .replacingOccurrences(of: " in ", with: " to ")
        let parts = normalized.components(separatedBy: " to ")
        guard parts.count == 2 else { return nil }
        let lhsTokens = parts[0].split(whereSeparator: \.isWhitespace).map(String.init)
        guard lhsTokens.count == 2, let value = Double(lhsTokens[0]) else { return nil }
        let u1 = lhsTokens[1], u2 = parts[1].trimmingCharacters(in: .whitespaces)

        if let a = lengthUnit(u1), let b = lengthUnit(u2) {
            return formatMeasurement(Measurement(value: value, unit: a).converted(to: b).value, unitLabel: u2, expr: trimmed)
        }
        if let a = massUnit(u1), let b = massUnit(u2) {
            return formatMeasurement(Measurement(value: value, unit: a).converted(to: b).value, unitLabel: u2, expr: trimmed)
        }
        if let a = dataUnit(u1), let b = dataUnit(u2) {
            return formatMeasurement(Measurement(value: value, unit: a.unit).converted(to: b.unit).value, unitLabel: b.label, expr: trimmed)
        }
        if let a = tempUnit(u1), let b = tempUnit(u2) {
            return formatMeasurement(Measurement(value: value, unit: a.unit).converted(to: b.unit).value, unitLabel: b.label, expr: trimmed)
        }
        return nil
    }

    private static func formatMeasurement(_ val: Double, unitLabel: String, expr: String) -> UnitConversionResult {
        let num = val.rounded() == val && abs(val) < 1e9 ? String(Int64(val)) : String(format: "%.4g", val)
        return UnitConversionResult(expression: expr, resultText: "\(num) \(unitLabel)", badgeLabel: "换算")
    }

    private static func lengthUnit(_ s: String) -> UnitLength? {
        ["km": .kilometers, "m": .meters, "cm": .centimeters, "mm": .millimeters, "mi": .miles, "ft": .feet, "in": .inches][s]
    }
    private static func massUnit(_ s: String) -> UnitMass? {
        ["kg": .kilograms, "g": .grams, "lb": .pounds, "oz": .ounces][s]
    }
    private static func dataUnit(_ s: String) -> (unit: UnitInformationStorage, label: String)? {
        switch s {
        case "tb": (.tebibytes, "TB")
        case "gb": (.gibibytes, "GB")
        case "mb": (.mebibytes, "MB")
        case "kb": (.kibibytes, "KB")
        default: nil
        }
    }
    private static func tempUnit(_ s: String) -> (unit: UnitTemperature, label: String)? {
        switch s {
        case "c", "°c", "摄氏度": (.celsius, "°C")
        case "f", "°f", "华氏度": (.fahrenheit, "°F")
        case "k": (.kelvin, "K")
        default: nil
        }
    }
}
