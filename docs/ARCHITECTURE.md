# 系统架构与 Clean Code 约束

## 模块划分

`Package.swift` 将工程拆分为四个正交 Swift 6 目标（`.swiftLanguageMode(.v6)`），**零外部依赖**：

1. **`LumakeyCore`**（`Sources/LumakeyCore`）：纯核心业务库，供主应用、MCP 服务及自动化检查程序共同复用。
   - 统一搜索与快捷引擎：`LauncherEngine` + `LauncherTextAndMath`（`OmniFilter` 统一排序：预小写化应用中文拼音、`^`/`0x` 安全求值、无前缀 Everything 文件、`ClipboardEntry` 历史、插件与系统命令）、`UnitAndCommandEngine`（换算、端口、网页、Mos 与内存指令）、`ClipboardMonitor`（隐私过滤、临时文件 GC）、`EverythingQuery`（原地 UTF-8 字节折叠匹配）、`EverythingIndex`（`24 B` 紧凑节点）、`EverythingSnapshotStore`（`LMKYIDX2` 紧凑二进制 `.lmkyidx` + O(1) 头部探测 + `mmap` 按需加载）、`EverythingIndex+FSEvents` + `EverythingFSEventWatcher`（macOS `FSEventStream` 增量更新）
   - 内置插件与系统遥测：`MosMouseService`（`MosConfig` 持久化、`MosEngine` `CGEvent.tapCreate` 物理滚轮过滤与 120Hz 平滑）、`SystemMonitorService`（`SystemMonitorSampler` Mach/IOKit/网络速率与 DVFS 硬件频率估算、`SystemMonitorConfig` 持久化）、`MarkdownDocumentParser`（Frontmatter / GFM 表格 / 代码块 / Callout / 任务清单 / 大纲提取）、`PluginSystem`
   - 运行时自洁与过程监管：`ProcessSupervisor`（超时强杀 + 64 KB 有界管道读取 + 活跃 PID 清单）、`MemoryStats`（`task_vm_info` 物理占用统计 + `malloc_zone_pressure_relief` 堆页回收）
   - QQ 式截图标注模型与合成：`ScreenshotModels`（9 种工具 / 6 色 / SML 线宽）、`ScreenshotCompositor`（像素 `#HEX` 采样、实时下采样马赛克预览与离屏 `CGContext` 合成）
   - 附加工作台与原生视觉：`FileModels`、`DirectoryScanner`（支持 `skipExtendedTags` 跳过慢速卷 Finder xattr 读取与 POSIX `stat` 目录mtime 检测）、`WorkspaceDirectoryCache`（48 项有界 LRU SWR 目录缓存）、`MediaClassifier`（含 `.markdown` 分类与扩展名快速分类）、`BatchRenamePlanner`、`VolumeInspector`、`VisionService`（CPU 计算设备绑定保障亚秒 OCR/抠图）、`VideoPlaybackCompat`（`Hev1ResourceLoader` 串行队列异步分块零拷贝 `'hev1' -> 'hvc1'` 实时转标 + 受控 `ffmpeg` 无损快封）、`PreviewPlaybackRegistry`（工作台侧边内嵌播放器弱引用注册与跨窗口自动暂停协同）、`NetworkTrafficModels`、`NetworkTrafficSampler`、`AppCacheService`（含 `.diskIndexSnapshot` 二进制索引快照分桶）、`CodeSigningInspector`、`UserFacingError`
2. **`Lumakey`**（`Sources/Lumakey`）：macOS SwiftUI + AppKit 菜单栏应用与无边框悬浮窗口前端。
   - 窗口、性能与真圆角拖拽：`FloatingPanelController`（`RoundedGlassContainerView` 9-slice `28pt` `.popover` 材质 `maskImage`、恒定 `880 × 544` 零跳变容器、隐藏 30s 自动销毁）、`FrostedWindowVisualEffectView`、`WindowLevelStore`（全局 `.floating` 置顶与小窗管理）、`IconCache`（`@2x` 紧凑位图化 + `12 MB` `totalCostLimit`）、`LiquidTheme`、`WindowChromeViews`（`SecondaryWindowScaffold` 居中微胶囊标题栏 + 置顶按钮、`SettingsSectionHeroHeader`、`SettingsToggleCardRow`、`GlassInputField`）、`AutoFocusSearchField`、`MenuBarAndWindowCoordinator`（混合智能 Dock 策略 + Dock 右键窗口菜单）、`GlobalHotKeyManager`、`LumakeyApp`
   - 系统脉搏悬浮监控：`SystemPulseWindowController` + `SystemPulseOverlayView`（`⌥M`、`hosting.sizingOptions = []` 防尺寸残影、顶部精简胶囊悬停/点击展开、屏幕边缘吸附贴边隐藏、Sparkline 趋势图与菜单栏实时读数）
   - 内置网络流量与缓存管理：`NetworkMonitorController` + `NetworkMonitorWindowView`（`⌥N`、进程流量排序与去向 Socket 检查）、`AppCacheSettingsView`（分桶盘点、一键清理与置顶/配置保护）
   - 截图标注、钉图与独立 OCR 引擎：`ScreenCaptureEngine`（`ScreenCaptureKit` 冻屏 + 窗口清单 + `CaptureOverlayPanel` 右键取消/重选）、`ScreenshotSessionState`、`ScreenshotCanvasView`、`ScreenshotChromeViews`、`ScreenshotToolbarView`、`PinWindowController` + `PinnedImageOverlayView`（`PinInteractionLayer` 首击拖拽、滚轮缩放、半透明调节与右键菜单）、`OCRResultWindowController`（独立可编辑/合并换行/置顶识字结果窗）
   - 统一搜索面板与设置：`AppViewModel*`（后台 `Task.detached` 并发排序、`displayedCandidates` 状态输出、事件驱动 `cachedVolumes` 与外置盘自动重索引、65ms 预览防抖）、`OverlayCommandView`、`OverlayBentoHomeView`（`76pt` 居中 Bento 卡片 + `0.32×` 超椭圆徽章）、`OverlayResultRows`、`OverlaySideLensView`、`MosPluginSettingsView`、`TelemetrySettingsView`、`SettingsDetailSectionsView`、`WelcomeAndSettingsView`、`PluginCenterView`
   - 独立窗口阅读与附加工作台：`DocumentReaderWindowView`、`MarkdownBlocksView`、`MediaSheets`（`ReadOnlyImageViewerSheet`、`BatchRenameSheet`、`WorkspaceHostView`）、`CinemaPlayerController` + `CinemaPlayerWindowView`（暗黑沉浸影院播放器 + 同目录视频播放列表/搜索/`连播` + 置顶/小窗 + IINA 一键直达）、`FileWorkspaceViews`、`WorkspaceContentViews` + `WorkspaceThumbnailPipeline`（列表/异步限流缩略图网格/双列紧凑视图 + `ThumbnailDecodeGate(4)` + `32 MB` 有界缓存）、`SidePreviewPanelView`、`SideLivePreviewCard`（居中图文/兼容视频预览舞台）、`AppNavigationState`（`PaneState` 缓存媒体计数）、`AppViewModel+Workspace`、`AppViewModel+Services`
3. **`lumakey-mcp`**（`Sources/LumakeyMCP`）：嵌入 `.app/Contents/MacOS/lumakey-mcp` 的独立可执行 stdio JSON-RPC 2.0 服务器。
4. **`LumakeyCheck`**（`Tests/LumakeyCheck`）：在 CommandLineTools 无 XCTest 环境下运行的确定性自检程序，覆盖核心引擎、Markdown 解析、统一搜索、进程超时强杀、Mos 配置、`MemoryStats` 与真实 `lumakey-mcp` 子进程测试。

## 内存自洁与资源生命周期规范

- **浮窗与独立窗口即关即毁**：
  - 主悬浮窗在隐藏 `30s` 后释放 `panel` 与 `NSHostingView`；独立窗口在 `NSWindowDelegate.windowWillClose` 中立即置空 `contentView = nil` 并回收堆内存页。
  - 双栏文件工作台在启动时不预扫描目录，首次打开时全异步加载目录并缓存至有界 `WorkspaceDirectoryCache`（48 项 LRU + SWR），关闭后保留最近 `16` 个热点目录以便下次秒开，仅回收大预览状态与超出部分。
- **空闲索引卸载与系统内存压响应**：
  - Everything 启动优先对本地 `LMKYIDX2` 二进制快照执行 `readHeaderMetadata(...)` O(1) 探测（仅读取前 4 KB 展示节点数而不常驻内存），切入文件模式或输入搜索词时再通过 `Data(..., options: .mappedIfSafe)` 内存映射恢复并启用 `EverythingFSEventWatcher`；主浮窗连续隐藏 `90s` 或收到系统 `.warning`/`.critical` 内存压力信号时卸载内存节点与缩略图缓存以便下次瞬时恢复。
- **子进程有界与零僵尸进程**：
  - 所有插件脚本与 `lsof` 通过 `ProcessSupervisor.shared.run(...)` 执行，单次读取上限 `64 KB`，超时自动 `terminate`/`SIGKILL`；面板隐藏及应用退出前调用 `terminateAll()`。
- **物理鼠标零空闲功耗**：
  - `MosEngine` 仅在开启开关且获得辅助功能权限时安装 `CGEventTap`，静止帧平滑定时器在位移趋零后自动 `invalidate()`。
- **Swift 6 并发与 Clean Code 门禁**：
  - `Sources/` 下**任意 `.swift` 文件严格不超过 300 行**（`scripts/verify-macos.sh` 自动化检查）；零 `@State` 宏依赖以确保纯 CommandLineTools 工具链稳定构建。
