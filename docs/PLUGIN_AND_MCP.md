# 插件系统与 MCP 接口规范

`Lumakey` 内置一套零常驻开销的插件规范，并通过同包交付的 `lumakey-mcp` 服务让 AI 编程助手可以读取规范、创建脚手架、验证语法并运行真实测试。

## 插件目录与 `plugin.json` v1 契约

用户插件统一存放于：
`~/Library/Application Support/Lumakey/Plugins/<plugin-id>/plugin.json`

最小示例：

```json
{
  "id": "uuid-gen",
  "name": "UUID 生成器",
  "version": "1.0.0",
  "description": "生成一行小写或大写 UUID",
  "mode": "script",
  "keywords": ["uuid", "guid"],
  "entry": "run.sh"
}
```

### 字段约定与运行模式

- `id`：仅允许小写字母、数字与连字符（`[a-z0-9-]+`），禁止路径穿越字符（`..`、`/`）。
- `mode`：
  - `script`：空闲时 **0 MB 内存占用**；仅在启动器触发或测试时通过子进程启动 `entry`，向 `stdin` 写入 JSON `{"query": "..."}`，读取 `stdout` 文本作为结果输出。
  - `view`：声明式轻量面板插件，按需加载展示结构化结果（当前 MVP 验证清单校验，交互式模板视图随 M1 扩展）。
- `keywords`：触发关键词列表，输入精确匹配或前缀匹配时直接提升在启动器结果顶部。
- `entry`：位于插件目录内的相对可执行脚本路径，不得逃逸插件根目录。

## 原生 Stdio MCP 服务器 (`lumakey-mcp`)

`lumakey-mcp` 采用无外部依赖的换行分隔 JSON-RPC 2.0 协议（可通过 `--plugins-dir <path>` 覆盖默认插件目录）。

### 暴露的资源 (`resources`)

- `lumakey://specs/plugin-v1`：返回最新插件目录约定、JSON 字段要求与脚本 stdin/stdout 示例。

### 暴露的工具 (`tools`)

| 工具名 | 参数 | 作用 |
| --- | --- | --- |
| `lumakey_list_plugins` | 无 | 扫描当前插件目录并返回所有有效及带诊断信息的插件摘要 |
| `lumakey_scaffold_plugin` | `id`, `name`, `keywords`, `description`, `mode`（可选） | 安全校验 ID 后在插件目录生成 `plugin.json` 与可执行示例 `run.sh` |
| `lumakey_validate_plugin` | `id` | 校验 manifest 格式、字段完整性、入口脚本存在性及防路径逃逸安全检查 |
| `lumakey_run_plugin_test` | `id`, `query` | 以受控子进程沙盒执行一次插件脚本并返回退出码、耗时与标准输出 |
