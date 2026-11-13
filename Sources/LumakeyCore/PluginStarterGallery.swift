import Foundation

public struct PluginStarterTemplate: Identifiable, Sendable, Hashable, Equatable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let description: String
    public let mode: PluginMode
    public let icon: String
    public let keywords: [String]
    public let config: [PluginConfigField]
    public let scriptBody: String

    public init(
        id: String,
        name: String,
        subtitle: String,
        description: String,
        mode: PluginMode,
        icon: String,
        keywords: [String],
        config: [PluginConfigField],
        scriptBody: String
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.description = description
        self.mode = mode
        self.icon = icon
        self.keywords = keywords
        self.config = config
        self.scriptBody = scriptBody
    }
}

public enum PluginStarterGallery {
    public static let templates: [PluginStarterTemplate] = [
        PluginStarterTemplate(
            id: "sys-ip-dns",
            name: "网络 IP 与 DNS 诊断",
            subtitle: "局域网 IPv4 · 主机名 · DNS 解析栈卡片",
            description: "即时读取本机活跃网卡 IPv4、LocalHostName、系统 DNS 服务器及可选公网出口 IP，点击即可复制。",
            mode: .view,
            icon: "network",
            keywords: ["ip", "dns", "netdiag"],
            config: [
                PluginConfigField(key: "interfaceHint", label: "首选网卡接口", type: .select, defaultValue: "en0", options: ["en0", "en1", "utun0"]),
                PluginConfigField(key: "fetchPublicIP", label: "查询公网出口 IP (1.2s 超时)", type: .boolean, defaultValue: "false")
            ],
            scriptBody: """
            #!/bin/zsh
            set -euo pipefail
            PAYLOAD="$(cat)"
            esc() { printf '%s' "$1" | tr '\\r\\n\\t' '   ' | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g'; }
            IFACE="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract config.interfaceHint raw -o - - 2>/dev/null || echo "en0")"
            FETCH_PUB="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract config.fetchPublicIP raw -o - - 2>/dev/null || echo "false")"
            LAN_IP="$(/usr/sbin/ipconfig getifaddr "$IFACE" 2>/dev/null || /usr/sbin/ipconfig getifaddr en0 2>/dev/null || echo "127.0.0.1")"
            HOST_VAL="$(/usr/sbin/scutil --get LocalHostName 2>/dev/null || hostname)"
            DNS_ONE="$(/usr/sbin/scutil --dns 2>/dev/null | awk '/nameserver\\[[0-9]+\\]/ {print $3; exit}' || true)"
            [[ -z "$DNS_ONE" ]] && DNS_ONE="系统自动"
            PUB_IP="按需开启"
            if [[ "$FETCH_PUB" == "true" ]]; then
              PUB_IP="$(/usr/bin/curl -fsS --max-time 1.2 https://api.ipify.org 2>/dev/null || echo "离线/超时")"
            fi
            cat <<EOF
            {"title":"本机网络与 DNS 诊断","subtitle":"活跃接口 $(esc "$IFACE") · 主机 $(esc "$HOST_VAL")","badge":"NETWORK","metrics":[{"key":"局域网 IP","value":"$(esc "$LAN_IP")"},{"key":"首选 DNS","value":"$(esc "$DNS_ONE")"},{"key":"主机名","value":"$(esc "$HOST_VAL")"},{"key":"公网出口","value":"$(esc "$PUB_IP")"}],"items":[{"title":"$(esc "$LAN_IP")","subtitle":"局域网 IPv4 ($IFACE) · 点击复制","icon":"wifi","badge":"LAN","copyText":"$(esc "$LAN_IP")"},{"title":"$(esc "$DNS_ONE")","subtitle":"当前主用 DNS 服务器","icon":"server.rack","badge":"DNS","copyText":"$(esc "$DNS_ONE")"}]}
            EOF
            """
        ),
        PluginStarterTemplate(
            id: "quick-hash-uuid",
            name: "批量 UUID 与摘要生成",
            subtitle: "SHA-256 · MD5 · 批量标准 UUID 卡片",
            description: "对输入文本（或剪贴板）计算 SHA-256 与 MD5 摘要，并一次生成多枚可一键复制的 UUID。",
            mode: .view,
            icon: "number.square.fill",
            keywords: ["hash", "uuidbatch", "digest"],
            config: [
                PluginConfigField(key: "uppercase", label: "输出大写字符", type: .boolean, defaultValue: "false")
            ],
            scriptBody: """
            #!/bin/zsh
            set -euo pipefail
            PAYLOAD="$(cat)"
            esc() { printf '%s' "$1" | tr '\\r\\n\\t' '   ' | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g'; }
            Q="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract query raw -o - - 2>/dev/null || true)"
            CLIP="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract clipboard raw -o - - 2>/dev/null || true)"
            UPPER="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract config.uppercase raw -o - - 2>/dev/null || echo "false")"
            SRC="${Q:-$CLIP}"
            [[ -z "$SRC" ]] && SRC="lumakey"
            SHA="$(printf '%s' "$SRC" | /usr/bin/shasum -a 256 | awk '{print $1}')"
            MD5V="$(printf '%s' "$SRC" | /sbin/md5 -q)"
            U1="$(/usr/bin/uuidgen)"
            U2="$(/usr/bin/uuidgen)"
            if [[ "$UPPER" != "true" ]]; then
              U1="${U1:l}"; U2="${U2:l}"
            else
              SHA="${SHA:u}"; MD5V="${MD5V:u}"
            fi
            cat <<EOF
            {"title":"摘要与批量 UUID","subtitle":"源文本长度 ${#SRC} 字符","badge":"CRYPTO","metrics":[{"key":"MD5","value":"$(esc "$MD5V")"},{"key":"UUID #1","value":"$(esc "$U1")"}],"items":[{"title":"$(esc "$SHA")","subtitle":"SHA-256 摘要","icon":"lock.shield","badge":"SHA256","copyText":"$(esc "$SHA")"},{"title":"$(esc "$MD5V")","subtitle":"MD5 摘要","icon":"number","badge":"MD5","copyText":"$(esc "$MD5V")"},{"title":"$(esc "$U1")","subtitle":"随机 UUID #1","icon":"sparkles","badge":"UUID","copyText":"$(esc "$U1")"},{"title":"$(esc "$U2")","subtitle":"随机 UUID #2","icon":"sparkles","badge":"UUID","copyText":"$(esc "$U2")"}]}
            EOF
            """
        ),
        PluginStarterTemplate(
            id: "port-killer",
            name: "端口监听进程排查",
            subtitle: "lsof 秒查端口占用 · 生成优雅释放命令",
            description: "输入端口号（如 3000 / 8080）排查占用进程 PID 与可执行程序，一键复制释放指令。",
            mode: .view,
            icon: "bolt.horizontal.circle.fill",
            keywords: ["port", "lsof", "listen"],
            config: [
                PluginConfigField(key: "defaultPort", label: "空查询默认排查端口", type: .text, defaultValue: "3000", placeholder: "3000")
            ],
            scriptBody: """
            #!/bin/zsh
            set -euo pipefail
            PAYLOAD="$(cat)"
            esc() { printf '%s' "$1" | tr '\\r\\n\\t' '   ' | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g'; }
            Q="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract query raw -o - - 2>/dev/null || true)"
            DEF_P="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract config.defaultPort raw -o - - 2>/dev/null || echo "3000")"
            PORT="$(printf '%s' "${Q:-$DEF_P}" | tr -cd '0-9')"
            [[ -z "$PORT" ]] && PORT="3000"
            LINE="$(/usr/sbin/lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1, $2, $9}' || true)"
            if [[ -z "$LINE" ]]; then
              cat <<EOF
            {"title":"端口 :$PORT 当前空闲","subtitle":"未检测到 TCP LISTEN 监听进程","badge":"FREE","metrics":[{"key":"目标端口","value":"$PORT"},{"key":"状态","value":"空闲可用"}],"items":[{"title":"lsof -nP -iTCP:$PORT -sTCP:LISTEN","subtitle":"复制终端复核命令","icon":"terminal","badge":"CMD","copyText":"lsof -nP -iTCP:$PORT -sTCP:LISTEN"}]}
            EOF
            else
              PROC_NAME="${LINE[(w)1]}"; PID_VAL="${LINE[(w)2]}"; ADDR_VAL="${LINE[(w)3]}"
              cat <<EOF
            {"title":"端口 :$PORT 已被占用","subtitle":"进程 $(esc "$PROC_NAME") (PID $PID_VAL)","badge":"LISTEN","metrics":[{"key":"进程名","value":"$(esc "$PROC_NAME")"},{"key":"PID","value":"$(esc "$PID_VAL")"},{"key":"监听地址","value":"$(esc "$ADDR_VAL")"}],"items":[{"title":"kill -15 $(esc "$PID_VAL")","subtitle":"复制优雅终止 $(esc "$PROC_NAME") 命令","icon":"xmark.octagon","badge":"SIGTERM","copyText":"kill -15 $(esc "$PID_VAL")"}]}
            EOF
            fi
            """
        ),
        PluginStarterTemplate(
            id: "shell-note",
            name: "快速追加灵感笔记",
            subtitle: "极速追加带时间戳 Markdown 速记",
            description: "将灵感或待办附带时间戳与标签快速追加到本地 Markdown 收件箱文件。",
            mode: .script,
            icon: "note.text.badge.plus",
            keywords: ["note", "memo", "inbox"],
            config: [
                PluginConfigField(key: "notesPath", label: "Markdown 笔记路径", type: .text, defaultValue: "~/Documents/Lumakey-Notes.md", placeholder: "~/Documents/Lumakey-Notes.md"),
                PluginConfigField(key: "tagPrefix", label: "默认标签前缀", type: .text, defaultValue: "#idea", placeholder: "#idea")
            ],
            scriptBody: """
            #!/bin/zsh
            set -euo pipefail
            PAYLOAD="$(cat)"
            Q="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract query raw -o - - 2>/dev/null || true)"
            RAW_PATH="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract config.notesPath raw -o - - 2>/dev/null || echo "~/Documents/Lumakey-Notes.md")"
            TAG="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract config.tagPrefix raw -o - - 2>/dev/null || echo "#idea")"
            NOTE_FILE="${RAW_PATH/#\\~/$HOME}"
            mkdir -p "$(dirname "$NOTE_FILE")"
            if [[ -n "${Q// /}" ]]; then
              TS="$(date '+%Y-%m-%d %H:%M')"
              printf -- '- [%s] %s %s\\n' "$TS" "$TAG" "$Q" >> "$NOTE_FILE"
              echo "已写入笔记 ($NOTE_FILE): [$TS] $TAG $Q"
            else
              [[ -f "$NOTE_FILE" ]] && tail -n 5 "$NOTE_FILE" || echo "笔记为空，输入内容即可追加至 $NOTE_FILE"
            fi
            """
        )
    ]

    public static func template(id: String) -> PluginStarterTemplate? {
        templates.first { $0.id == id }
    }

    public static func isInstalled(templateID: String, in rootDir: URL = PluginSystem.defaultPluginsDirectory()) -> Bool {
        FileManager.default.fileExists(atPath: rootDir.appendingPathComponent(templateID).appendingPathComponent("plugin.json").path)
    }

    @discardableResult
    public static func install(
        templateID: String,
        in rootDir: URL = PluginSystem.defaultPluginsDirectory(),
        overwrite: Bool = true
    ) throws -> PluginDescriptor {
        guard let tpl = template(id: templateID) else {
            throw LumakeyError.pluginInvalid("未知精选插件模板：\(templateID)")
        }
        let pluginDir = rootDir.appendingPathComponent(tpl.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: pluginDir.path) {
            guard overwrite else { throw LumakeyError.pluginInvalid("插件 '\(tpl.id)' 已安装") }
            try FileManager.default.removeItem(at: pluginDir)
        }
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let entryName = "run.sh"
        let scriptURL = pluginDir.appendingPathComponent(entryName)
        try tpl.scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let manifest = PluginManifest(
            id: tpl.id,
            name: tpl.name,
            version: "1.0.0",
            description: tpl.description,
            mode: tpl.mode,
            keywords: tpl.keywords,
            entry: entryName,
            author: "Lumakey Official",
            icon: tpl.icon,
            config: tpl.config
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: pluginDir.appendingPathComponent("plugin.json"), options: .atomic)
        return PluginSystem.loadPlugin(at: pluginDir, in: rootDir)
    }
}

extension PluginSystem {
    public static let specMarkdown: String = """
    # Lumakey Plugin Specification (v1)
    - Directory: ~/Library/Application Support/Lumakey/Plugins/<id>/
    - Manifest (`plugin.json`): id (`[a-z0-9-]+`), name, version, description, mode (`script` | `view`), keywords (`[String]`), entry (relative path)
    - Script protocol: reads `{"query":"..."}` JSON from stdin, writes plain result text to stdout, exits 0.
    """

    public static let specV2Markdown: String = """
    # Lumakey Plugin Specification (v2)
    - Backward-compatible with v1 `plugin.json`; optional v2 fields: `author`, `icon` (SF Symbol), `hotkey`, `config` (`[PluginConfigField]` with `key`, `label`, `type`: `text|secret|boolean|select`, `defaultValue`, `placeholder`, `options`, `required`).
    - State & Config: persisted in `plugin-state.json` (`isEnabled` + `configValues`), hot-reloaded with 350ms FSEvents debounce.
    - Enriched stdin JSON: `{"query":"...","mode":"script|view","config":{...},"clipboard":"..."}`.
    - Declarative `view` stdout JSON (`PluginViewPayload`): `{"title":"...","subtitle":"...","badge":"...","markdown":"...","metrics":[{"key":"...","value":"..."}],"items":[{"title":"...","subtitle":"...","icon":"...","badge":"...","copyText":"...","openURL":"...","commandArgs":["..."]}]}` (gracefully degrades to plain text if stdout is non-JSON).
    """
}
