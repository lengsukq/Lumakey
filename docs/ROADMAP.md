# 版本路线图

本项目采用“核心快捷闭环先跑通 -> 原生体验与视觉精雕 -> 大容量与格式增强”的稳健演进路线，严禁在文档中混淆“已实现”与“计划中”的功能。

## M0：核心引擎与 MCP 垂直闭环（已完成）

- 确立 Swift 6 (`arm64` only) 四目标架构：`LumakeyCore`、`Lumakey`、`lumakey-mcp`、`LumakeyCheck`。
- 落地“Everything 检索”紧凑内存树、多根目录索引与过滤 DSL（`ext:` / `folder:` / `video:` / `pic:` / `path:` / `!` / `|`）。
- 落地系统服务直连：外置卷 `statfs` 探测与宿主机工具链识别、选区截图、浮动钉屏窗、离线 OCR/条码与主体抠图、`script` 插件与 `lumakey-mcp` 联调。
- 落地按需文件工作台：单双栏切换、多标签、批量重命名安全预览、320pt 侧边实时预览与只读看图/播片。

## M1：Kitty-Tools 形态转型与 iOS 液态玻璃重塑（已完成 v0.4.0）

- 升级为 **菜单栏常驻 (`LSUIElement`) + 全局热键悬浮快捷中枢**（`⌥Space`、`⌥F`、`⌥C`、`⌥A`、`⌥O`、`⌥E`），文件管理收敛为按需附加工具。
- 重构全套 **iOS 液态玻璃界面**：真实 `NSVisualEffectView` 背景折射、`28pt` 连续圆角外壳、`3×2` Bento 控制中心、常驻应用坞、侧边玻璃预览镜与按键提示底栏。
- 落地 **零卡顿 OmniSearch**（后台线程并发排序、`IconCache`、`NSPanel` 恒定高度无动画切换）、**QQ 式原生 `ScreenCaptureKit` 截图标注引擎**、**内置 Mos 鼠标平滑** 与 **本机 `.dmg` / `/Applications` 安装脚本**。

## M2：极速事件流与多媒体极端场景增强（计划中）

- **Everything 引擎增量升级**：接入 `getattrlistbulk` 高速目录遍历与 `FSEvents` 实时索引增量更新。
- **插件体验与自定义热键升级**：支持热键可视化录制自定义、插件目录文件变化热重载，以及 `view` 模式声明式结果卡片渲染。
- **外置 NTFS 安全读写辅助**：在检测到宿主机已安装 `ntfs-3g` 且确认卷无脏标记（clean unmount）时，提供一键安全授权重挂为读写。
- **异构视频格式与外挂字幕**：利用宿主机 `ffprobe` / `ffmpeg` 实现 `MKV` / `AVI` / `WebM` / `TS` 转封装直播及 `.srt` / `.ass` 字幕轨道支持。
