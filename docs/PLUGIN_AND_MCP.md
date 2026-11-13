# 插件系统与 MCP 接口规范

`Lumakey` 内置一套零常驻开销的 **Plugin v2** 规范（完全向后兼容 v1），支持 `FSEvents` 目录热重载、可视化配置表单、启停持久化与原生结构化 `view` 卡片渲染，并通过同包交付的 `lumakey-mcp` 服务让 AI 编程助手可以读取规范、一键安装官方示例、验证语法并运行真实测试。

## 插件目录与 `plugin.json` v2 契约

用户插件统一存放于：
`~/Library/Application Support/Lumakey/Plugins/<plugin-id>/plugin.json`（启停状态与用户配置持久化于同级 `plugin-state.json`）

完整示例（`author`、`icon`、`hotkey`、`config` 均为可选字段，v1 清单无需修改即可继续运行）：

```json
{
  "id": "sys-ip-dns",
  "name": "网络 IP 与 DNS 诊断",
  "version": "1.0.0",
  "description": "即时读取本机活跃网卡 IPv4、主机名与系统 DNS 卡片",
  "mode": "view",
  "keywords": ["ip", "dns", "netdiag"],
  "entry": "run.sh",
  "author": "Lumakey Official",
  "icon": "network",
  "hotkey": "⌥⇧I",
  "config": [
    { "key": "fetchPublicIP", "label": "查询公网出口 IP (1.2s 超时)", "type": "boolean", "defaultValue": "false" }
  ]
}
```

### 字段约定、异步输入与 `view` 渲染协议

- `id`：仅允许小写字母、数字与连字符（`[a-z0-9-]+`），禁止路径穿越字符（`..`、`/`）。
- `entry`：位于插件目录内的相对可执行脚本路径，不得逃逸插件根目录。
- **异步标准输入 (`stdin`)**：空闲时 **0 MB 内存占用**；仅在触发时通过 `PluginSystem.runPluginAsync(...)` 在后台脱离主线程调用 `ProcessSupervisor.shared.run(...)` 受控拉起子进程，向 `stdin` 写入 JSON：
  `{"query": "...", "mode": "script|view", "config": {"key": "val"}, "clipboard": "..."}`。
- `mode`：
  - `script`：读取 `stdout` 纯文本作为结果输出。
  - `view`：脚本向 `stdout` 输出符合 `PluginViewPayload` 契约的 JSON（含 `title`、`subtitle`、`badge`、可选 `markdown`、指标对 `metrics: [{key, value}]` 与交互项 `items: [{title, subtitle, icon, badge, copyText, openURL, commandArgs}]`），由主浮窗侧边预览镜 `PluginStructuredViewCard` 原生渲染为液态玻璃交互卡片（按 `Esc` 优先关闭卡片；若输出非 JSON 则平滑回退为纯文本展示）。
- **目录实时热重载与示例商店**：`PluginDirectoryWatcher` 通过 `FSEventStreamCreate`（`350ms` 防抖）监听插件目录增删改自动刷新；设置页「插件与 MCP」内置 4 款 `PluginStarterGallery` 官方脚手架（`sys-ip-dns`、`quick-hash-uuid`、`port-killer`、`shell-note`）供一键安装。

## 内置开发者瑞士军刀与快捷短语

除外部插件外，`LumakeyCore` 原生内置零子进程开销的 `DevToolkitEngine`（时间戳秒/毫秒双向解析、UUID 生成、高强度随机密码、Base64、URL 编解码、MD5/SHA-256 摘要、JWT 离线解码、JSON 美化校验、`#HEX`/`rgb`/`hsl` 色板转换、`CIQRCodeGenerator` 高清二维码生成与复制/贴图）与 `SnippetStore`（`snippets.json`，支持 `;` 前缀触发及 `{{date}}`、`{{time}}`、`{{datetime}}`、`{{uuid}}`、`{{clipboard}}` 动态展开）。

## 原生 Stdio MCP 服务器 (`lumakey-mcp`)

`lumakey-mcp` 采用无外部依赖的换行分隔 JSON-RPC 2.0 协议（可通过 `--plugins-dir <path>` 覆盖默认插件目录）。

### 暴露的资源 (`resources`)

- `lumakey://specs/plugin-v2`（同时兼容保留 `lumakey://specs/plugin-v1`）：返回最新 `plugin.json` v2 字段定义、丰富 `stdin` 上下文与 `view` 模式 `PluginViewPayload` JSON 模板。

### 暴露的工具 (`tools`)

| 工具名 | 参数 | 作用 |
| --- | --- | --- |
| `lumakey_list_plugins` | 无 | 扫描当前插件目录并返回所有有效/无效状态、启用状态及诊断摘要 |
| `lumakey_scaffold_plugin` | `id`, `name`, `keywords`, `description`, `mode`（可选） | 安全校验 ID 后在插件目录生成 `plugin.json` 与可执行示例 `run.sh`（支持 `script` / `view` 模板） |
| `lumakey_install_starter_plugin` | `id` | 一键安装内置官方示例插件（`sys-ip-dns`、`quick-hash-uuid`、`port-killer`、`shell-note`） |
| `lumakey_validate_plugin` | `id` | 校验 manifest 格式、字段完整性、入口脚本存在性及防路径逃逸安全检查 |
| `lumakey_set_plugin_enabled` | `id`, `enabled` | 启用或停用指定插件并同步持久化至 `plugin-state.json` |
| `lumakey_remove_plugin` | `id` | 安全校验防路径逃逸后移除指定插件目录并清理状态记录 |
| `lumakey_run_plugin_test` | `id`, `query` | 以受控子进程沙盒执行一次插件脚本并返回 `exitCode`、`durationMs`、`stdout` 与 `stderr` |
