# 当前实现状态

本文件如实记录当前仓库中已经编写并经过校验的真实实现，规划中能力见 [版本路线图](ROADMAP.md)。

## 已完成与已验证 (v0.7.0)

- **Liquid Glass v2 视觉精雕与全键盘极客流 (`LiquidTheme`, `LiquidGlassComponents`, `OverlayCommandView`, `OverlayFilterStripsView`, `OverlayBentoHomeView`)**：
  - 引入严格同心圆角阶梯（外窗 `28pt` -> 搜索栏 `22pt` -> 卡片 `18pt` -> 候选行 `14pt`）与 `DoubleSpecularBorder` 双层高光镜面描边，升级 `LiquidBentoTileStyle` 按压微缩放阻尼回弹、`LiquidKeyHintBadge` 键帽与 `⌘1..9` 行级快选角标；
  - `AutoFocusSearchField` 接入灵动键盘操作流：`⌘1`..`⌘9` 秒执行对应行、`⌘C` / `⇧⌘C` 直接复制当前候选文本/路径/算式或色值、`⌘Return` 次级动作（访达定位或独立窗口打开）；Bento 首页升级原生动图录屏 (`⌥G`) 主磁贴及脉搏 (`⌥M`) / 插件 / 备份底栏快捷胶囊。
- **应用使用频率/时长智能排序与常驻钉选 (`AppUsageService`, `AppUsageTrackerController`, `LauncherEngine`)**：
  - 基于 `NSWorkspace` 前台激活时长累计（单次封顶防挂机失真）+ Lumakey 启动计数 + 14 天半衰期指数时间衰减计算综合权重，冷启动零数据时通过 `AppSystemUsageProbe` 一次性融合 Spotlight `kMDItemUseCount`/`kMDItemLastUsedDate`、Dock 固定栏与常用应用兜底并原子落盘 `~/Library/Application Support/Lumakey/app-usage.json`；
  - 支持最多 8 个钉住应用（`pinnedBundleIDs`）：Bento 常驻坞、空状态列表与带关键词全搜（`usageBoosts`）均优先置顶已钉应用与高频高时长应用，候选行与侧边详情镜提供图钉徽标、`usageSummary` 及「钉在常用栏 / 取消钉住 / 重置统计」菜单。
- **零依赖原生区域 GIF 动图录制 (`GifEncoderService`, `GifCaptureController`, `GifRecordingHUDView`)**：
  - 复用 `ScreenCaptureKit` (`SCStream` BGRA 帧采集) + `ImageIO` (`CGImageDestinationCreateWithURL` 流式 GIF89a 编码)，无需 `ffmpeg`：支持交互框选区域、10/15/24 FPS、Retina 1x 自动降采样、相邻近似静止帧差值合并压缩（最长 60s 有界保护）与灵动岛悬浮录制控制条 (`⌥G` / 菜单栏 / 搜索命令 `gif`/`录屏`)；
  - 录制落盘至 `NSTemporaryDirectory()/lumakey-gifs/`（纳入 `AppCacheService` `.gifCaptures` 缓存桶管理），完成后自动以 `com.compuserve.gif` + `public.file-url` 双格式写入系统剪贴板并支持一键置顶预览或访达定位。
- **全局热键可视化录制与三层冲突检测 (`HotKeyModels`, `HotKeyConflictDetector`, `GlobalHotKeyManager`, `HotKeySettingsView`)**：
  - 持久化 `~/Library/Application Support/Lumakey/hotkeys.json`，通过 `GlobalHotKeyManager.applyConfig(...)` 动态热重绑全部 10 项全局动作（新增区域 GIF 录制 `⌥G` 与一键本地备份，支持清空解绑与单键恢复默认）；
  - `HotKeyRecorderControl` 录制时实时执行三层冲突诊断：应用内动作/已启用插件热键互斥拦截、`~/Library/Preferences/com.apple.symbolichotkeys.plist` 系统快捷键与常见保留组合提示，以及 `Carbon` `RegisterEventHotKey` 真实第三方占用探测。
- **本地加密校验备份与原生 WebDAV 云同步 (`BackupArchiveService`, `WebDAVClient`, `BackupCoordinator`, `BackupSettingsView`)**：
  - 打包生成含 `manifest.json`（每文件 `CryptoKit.SHA256` 校验与版本元数据）的 `.lumakeybackup` 归档，覆盖核心配置 JSON、自定义插件目录与可选剪贴板历史；导入恢复前强制校验完整性与防路径穿越（拒绝 `..`、绝对路径与符号链接），先快照当前配置再原子替换热重载；
  - 纯 `Foundation.URLSession` 实现 RFC 4918 WebDAV 客户端（`PROPFIND`/`MKCOL`/`PUT`/`GET`/`DELETE`，兼容坚果云、Nextcloud、群晖与 iCloud Drive 本地同步目录），密码经 `Security` Keychain 安全存储，支持远端快照列表恢复与最多保留最近 10 份自动轮转。
- **插件系统 v2、开发者瑞士军刀与快捷短语 (`PluginRuntimeAndWatcher`, `DevToolkitEngine`, `SnippetStore`, `PluginCenterView`, `SnippetsSettingsView`)**：
  - `plugin.json` 向后兼容扩展 `author`/`icon`/`hotkey`/`config` 表单字段，新增 `plugin-state.json` 启停与配置持久化、`ProcessSupervisor.runAsync` 异步子进程执行、丰富 `stdin` 上下文（`query`/`mode`/`config`/`clipboard`）、`PluginDirectoryWatcher` (`FSEvents` 300ms 防抖热重载) 与 5 款一键安装的 `PluginStarterGallery` 官方脚手架；
  - 原生渲染 `mode: "view"` 返回的 `PluginViewPayload` 结构化交互卡片（`PluginStructuredViewCard`，支持列表动作复制/打开 URL/重跑脚本，`Esc` 优先收起卡片）；`lumakey-mcp` 同步升级 `lumakey://specs/plugin-v2` 资源与启停/安装/移除工具；
  - 内置零依赖 `DevToolkitEngine`（时间戳双向互转、Base64、URL 编解码、JWT 离线解码、JSON 美化校验、UUID/纳米 ID、MD5/SHA1/SHA256/SHA512、`#HEX`/`rgb`/`hsl` 色板预览、`CoreImage` `CIQRCodeGenerator` 二维码生成并支持一键复制 PNG 或贴图置顶）与 `SnippetStore`（`snippets.json`，支持 `;` 前缀触发与 `{{date}}`/`{{time}}`/`{{datetime}}`/`{{uuid}}`/`{{clipboard}}` 动态占位符展开）。
- **Clean Code 架构拆分与检索精度优化 (`SystemDisplayPreferences`, `EverythingIndex`, `MarkdownDocumentParser`)**：
  - 新增 `SystemDisplayPreferences` 监听 `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` 提供 O(1) 无障碍透明度/对比度缓存，消除渲染帧 IPC 查询；`EverythingIndex.search` 升级为前缀/精确/深度相关性分桶排序（收集 `limit * 8` 候选择优）；`MarkdownDocumentParser` 升级为 `Substring` 零分配行切片与单遍内联解析；拆分超长视图与控制器文件确保 `Sources/*.swift` 全量严格 `<= 300` 行；`app.lumakey.macos` 升级至 `0.7.0` (build `16`)。

## 已完成与已验证 (v0.6.5)

- **全栈性能优化（启动与空闲内存降幅、零分配检索、有界缩略图与底层采样减负）**：
  - **按需常驻与 `@2x` 紧凑图标 (`AppViewModel+IndexCache`, `EverythingSnapshotStore`, `IconCache`)**：启动阶段仅通过 `readHeaderMetadata(...)` O(1) 读取 `LMKYIDX2` 快照头节点数而不提前驻留全盘节点数组，仅在切入文件模式或输入检索词时 `mmap` 载入（隐藏 `90s` 自动卸载并保持节点计数显示）；移除启动预热 64 个全尺寸 `.icns` 图标（最高 1024px/4MB 级多图），改为按需将 Dock Top 8 图标离屏光栅化为紧凑 `@2x` 位图（`12 MB` `totalCostLimit` 上限）并异步检测 `HostToolingStatus`；
  - **24B 紧凑节点与零堆分配 UTF-8 匹配 (`EverythingIndex`, `EverythingQuery`)**：`IndexedNode` 移除死字段 `sizeBytes`/`modifiedAt` 与冗余小写副本后步长缩减为 `24 B`，查询引擎改用原地 ASCII 大小写折叠 UTF-8 字节扫描与按需后缀提取（消除 24 万次重复字符串分配）；
  - **热路径零多余计算与并发限流 (`LauncherEngine`, `FileModels`, `MediaClassifier`, `WorkspaceThumbnailPipeline`, `FileWorkspaceViews`)**：浮窗隐藏期间跳过候选排序与剪贴板空转重算、按键检索加入 `10ms` 防抖，预计算 `InstalledAppItem` 与 `PluginDescriptor` 小写字段，拆分 `LauncherTextAndMath.swift`，`FastFormatters` 以纯算术与线程安全 `localtime_r` 替代逐行 `ByteCountFormatter`/`DateFormatter` 分配，`PaneState` 缓存 7 类媒体统计，工作台缩略图经 `ThumbnailDecodeGate(4)` 与 `kCGImageSourceShouldCache: false` 限流防爆仓并于关窗/释放内存时同步清空 `WorkspaceThumbnailCache`；
  - **遥测/剪贴板轮询降噪与 Release 裁剪 (`SystemMonitorService`, `AppViewModel+Services`, `scripts/build-macos.sh`)**：缓存 `AppleSmartBattery` / `IOAccelerator` `io_service_t` 句柄并节流 `statfs("/")`，剪贴板空闲轮询放宽至 `1.5s`（配合呼出浮窗即时捕获），Release 启用 `-Xswiftc -O -Xlinker -dead_strip` + `strip -x`；`app.lumakey.macos` 升级至 `0.6.5` (build `15`)。

## 已完成与已验证 (v0.6.4)

- **截图后全路径自动写入系统剪贴板（即截即粘）**：
  - `ScreenshotCompositor` 新增通用剪贴板双格式写入（`copyImageToPasteboard(_:scale:to:)`、`copyImageFileToPasteboard(at:to:)` 同时写入带逻辑缩放尺寸的 `.png` 与 `.tiff`）与剪贴板快照恢复（`PasteboardSnapshot.capture`/`restore`）；
  - `ScreenCaptureCoordinator` + `ScreenshotCanvasView` + `ScreenshotToolbarView`：交互截图框选、窗口吸附及完成涂鸦/文字/序号标注后自动将合成图像写入 `NSPasteboard.general`，按「完成 (`Enter` / `⌘C` / 双击)」「钉图」「保存」「抠图」均保留或写入最新截图至剪贴板，`Esc`/右键取消时无痕还原原剪贴板内容（单按 `C` 复制 HEX 色值例外）；
  - `AppViewModel+Services` 在截图过程中暂停 600ms 剪贴板轮询防中间态污染历史，结束即同步 `capturePasteboardOnceIfChanged()`；`PinnedImageOverlayView` 抠图完成后自动复制透明主体 PNG，`OCRResultWindowController` 无文字时自动保留原图在剪贴板；`app.lumakey.macos` 升级至 `0.6.4` (build `14`)。

## 已完成与已验证 (v0.6.3)

- **工作台零阻塞异步加载、二进制 `mmap` 索引快照与 `FSEvents` 增量同步**：
  - `EverythingSnapshotStore` + `EverythingIndex+FSEvents` + `EverythingFSEventWatcher`：持久化紧凑二进制快照 `LMKYIDX1` 至 `~/Library/Caches/com.queensu.lumakey/everything-index/*.lmkyidx`，冷启动优先使用 `Data(..., options: .mappedIfSafe)` 秒开恢复索引，并通过 `FSEventStreamCreate`（仅监听本机与快速卷）以 `0.9s` 防抖增量重扫变更目录；
  - **工作台异步 SWR 与慢卷优化 (`AppViewModel+Workspace`, `WorkspaceDirectoryCache`, `DirectoryScanner`)**：`ensureWorkspaceLoaded()`/`refreshLocations()`/`refreshDirectory(pane:forceRescan:)` 全面异步化至后台 `Task.detached`，移除主线程阻塞扫描（如 `macfuse`/NTFS/SMB 跳过 `.tagNamesKey` 扩展属性读取），引入 `WorkspaceDirectoryCache`（48 项 LRU + POSIX `stat` mtime 校验，关窗保留最近 16 项），`WorkspaceContentViews` 与 `SideLivePreviewCard` 改用 `IconCache.shared.icon(for:)` 消除逐行主线程 `NSWorkspace.icon(forFile:)` 阻塞；
  - `AppCacheService` + `AppCacheSettingsView` 新增 `.diskIndexSnapshot` 缓存分桶可视化管理，设置内提供手动「重建磁盘缓存」，主浮窗索引空闲卸载延长至 `300s`；`app.lumakey.macos` 升级至 `0.6.3` (build `13`)。

## 已完成与已验证 (v0.6.2)

- **系统脉搏悬浮窗贴边自适应排布与零留白紧凑重构**：
  - `PulseDockEdge` + `UnconstrainedPulseHostingView`：解除 `NSHostingView.intrinsicContentSize` 对 `NSPanel` 缩窗尺寸的钳制，统一状态机 `reconcilePresentationState(animate:)`，彻底消除折叠为胶囊或贴边时残留空白大框的问题；
  - **贴顶横向 / 贴边竖行自适应排版**：贴靠屏幕顶部展示 `356 × 34` 精致横向指标条（CPU / 内存 / 功耗 / 网速），贴靠左右侧边展示 `58 × 182` 竖行纵列卡片；展开态缩紧至 `354 × 318` `.top` 对齐消除顶部大块空白并支持背景拖拽贴边；
  - `app.lumakey.macos` 升级至 `0.6.2` (build `12`)。

## 已完成与已验证 (v0.6.1)

- **工作台与独立窗口播放联动防双音轨**：
  - `PreviewPlaybackRegistry` + `InlineAVPlayerRepresentable`：追踪文件工作台侧边栏内嵌音视频播放器，并在触发「独立窗口播放」「视频置顶」「外部播放器打开」、双击打开媒体或其他独立窗口路由时自动调用 `pauseAll()` 暂停工作台预览（保留当前播放画面不清空）；影院转交 IINA 时同步暂停自身播放器。
  - `app.lumakey.macos` 升级至 `0.6.1` (build `11`)。

## 已完成与已验证 (v0.6.0)

- **内置网络流量与去向监控 (`⌥N`) + 应用缓存管理**：
  - `NetworkTrafficModels` + `NetworkTrafficSampler`：免 Root 调用 `/usr/bin/nettop -L 1 -J bytes_in,bytes_out,interface,state -x -n` 采集实时进程 `↓/↑` 速率与累计字节，支持 `proc_pidpath` 归属应用、Socket 远程 `IP:port`/接口/状态/服务标签及异步 `getnameinfo` 反向 DNS 去向追踪；窗口与面板关闭时采样立即停止（0% 后台 CPU）；
  - `AppCacheService` + `AppCacheSettingsView`：按桶盘点并按需清理 `lumakey-clipboard`、截图/钉图临时文件、`lumakey-cutouts`、`lumakey-cinema` 与内存索引（同时保护置顶文件与 `~/Library/Application Support/Lumakey`）；命令口令 `流量`/`network`、`缓存`/`cache` 直达。
- **毛玻璃同心大圆角视效与居中重构**：
  - `FrostedWindowVisualEffectView` + `LiquidTheme` + `FloatingPanelController`：主搜索栏、Bento 控制中心、系统脉搏胶囊与二级窗口全面升级半透明毛玻璃材质，Bento 卡片统一垂直居中 `76pt` / `22pt` 圆角 + `44pt` `0.32×` 超椭圆徽章，修复系统脉搏折叠胶囊回缩尺寸残影（`hosting.sizingOptions = []`）。
- **图片置顶、视频置顶、小窗与同目录视频播放列表**：
  - `WindowLevelStore` + `WindowChromeViews`：支持只读看图窗、OCR 窗、Markdown 阅读器、影院播放器与文件工作台的 `.floating` 窗口置顶切换与 `520×300` 小窗浮层；
  - `CinemaPlayerController` + `CinemaPlayerWindowView`：自动扫描同级目录视频生成播放列表（带搜索与 `连播` 自动续播），并将 `Hev1ResourceLoader` 改造为串行 `loaderQueue` 异步分块供给以消除 4K HEVC 起播卡顿。
- **独立工程与 Clean Code 门禁**：
  - `app.lumakey.macos` 升级至 `0.6.0` (build `10`)，`Sources/` 全部 `.swift` 文件均不超过 300 行且零 `@State`/`@FocusState` 宏依赖。

## 已完成与已验证 (v0.5.3)

- **独立工程与 Clean Code 门禁**：
  - 独立仓库位于 `/Volumes/lightlsle/Code/Lumakey`，`app.lumakey.macos` (`0.5.3`, build `9`)，零外部依赖；
  - `Sources/` 下全部 `.swift` 文件严格拆分，单文件均不超过 300 行。
- **暗黑沉浸式 4K 影院播放器与 `'hev1'` / MKV 硬件解码兼容 (`VideoPlaybackCompat` & `CinemaPlayerWindowView`)**：
  - 针对主流 4K HEVC `.mp4` 使用 `'hev1'` 标签导致 `AVPlayer` 黑屏/只出声的问题，新增零拷贝 `Hev1ResourceLoader`（`AVAssetResourceLoaderDelegate` 流式将 `moov` 中的 `'hev1'` 动态映射为 `'hvc1'`），无需写临时文件即可直接调用 Apple Silicon VideoToolbox 硬件解码（`SideLivePreviewCard` 右侧预览与独立影院窗口均受益）；
  - 针对伪装 `.mp4` 扩展名的 `Matroska / WebM / FLV / TS` 视频，自动调用 `ffmpeg` 无损极速重封装至临时 `.mp4` 并在关闭窗口时自动销毁；
  - 全新 `.darkAqua` 无边框影院界面：移除冗杂浅色顶栏与双层边框，采用黑曜石全画幅 + 红绿灯同排自动隐藏暗色磨砂 HUD（文件名、分辨率/硬解徽标、上下集、倍速菜单、右侧选集抽屉、一键用 IINA/外部播放器打开）。
- **混合智能 Dock 图标策略 (`MenuBarAndWindowCoordinator.syncDockPolicy`)**：
  - 在关闭全部标准窗口时保持零扰的纯菜单栏 `.accessory` 模式（或尊重“常驻 Dock”设置）；一旦打开 **文件工作台、影院播片、文档阅读、只读看图、OCR 识字或设置** 等任意窗口，立即自动切换为 `.regular` 在底部程序坞显示图标并支持 `⌘Tab` 与点击最小化恢复/Dock 右键窗口列表，关窗即收起。
- **稳定 macOS 证书签名与 TCC 免重授权体系 (`CodeSigningInspector` & `setup-local-signing.sh`)**：
  - `scripts/build-macos.sh` 自动优先选用钥匙串中的 `Developer ID Application`、`Apple Development` 或 `Lumakey Local Signer` 证书按内到外精确签名，不再依赖每次构建都变化的 Ad-hoc `cdhash`；`scripts/install-macos.sh` 改为 `rsync -a --delete` 原位同步更新；
  - 设置首页新增实时签名状态诊断卡与一键复制 `scripts/setup-local-signing.sh` 命令入口，运行一次生成 10 年受信任本地代码签名证书后，后续构建升级不再重复索要「辅助功能 / 屏幕录制」权限。
- **全页面与二级页面精致化布局升级 (`WindowChromeViews` & `SettingsDetailSectionsView`)**：
  - 为 `DragRegionNSView` 添加 `intrinsicContentSize = 1×1`，从根源消除 `WindowDragRegion` 纵向撑高标题栏与 Bento 首页的问题；
  - 新增 `SecondaryWindowScaffold`，统一所有独立二级窗口（OCR 识字、文件工作台、Markdown/代码阅读器、只读看图、影院播片、欢迎引导、流光设置）的 `28pt` 居中标题栏微胶囊与紧凑顶边距，去除多余左缩进空白与工作台双层顶栏；
  - 新增 `SettingsSectionHeroHeader`、`SettingsToggleCardRow`、自适应 `GlassInputField` 与双列/卡片式二级设置页面（含可点击试用的 Everything DSL 语法速查、剪贴板隐私规则卡、插件空态、热键网格与架构理念三支柱）。
- **开箱即用全盘 + 外置磁盘 POSIX Everything 秒搜**：
  - `EverythingScope.allVolumes` 设为默认检索范围并在应用启动及磁盘挂载/卸载时自动重建索引，直接覆盖本机主目录与全部外置 SSD / NTFS 大容量磁盘；
  - `EverythingIndex` 改用 POSIX `opendir`/`readdir`（`d_type` 免逐文件 `stat` RPC）、多卷轮询 BFS 队列与 `merging(_:)` 两阶段合并，毫秒级出图本机/SSD 文件后平滑并入慢速 FUSE/NTFS 外置盘，命中条目按需补齐大小与修改时间。
- **多排序、多筛选、多视图文件工作台与居中预览舞台 (`⌥E`)**：
  - `DirectoryScanner` 与 `FileModels` 新增创建时间/扩展名排序、`foldersFirst` 文件夹置顶、`WorkspaceMediaFilter`（全部/文件夹/图片/视频/音频/文档/压缩包）与 `WorkspaceDisplayMode`（列表详情 / 异步缩略图网格 / 紧凑双列）；
  - `SideLivePreviewCard`、`SidePreviewPanelView`、`OverlaySideLensView`、`ReadOnlyImageViewerSheet` 统一将横向/竖向图片与视频水平垂直居中呈现在右侧预览舞台；修正 `OCRResultWindowController` 顶栏纵向拉伸问题。
- **高对比度液态玻璃与零跳动 Tab 切换 (`880 × 544` 恒定面板)**：
  - `RoundedGlassContainerView` 切换至自适应浅/深色 `.popover` 材质，配合 `CrispSearchTextField`（关闭 vibrancy）与 `LiquidColors` 高对比主副文字/输入胶囊/边缘描边动态令牌，彻底解决浅色背景下文字与占位符泛白不清的问题；
  - 主浮窗锁定 `880 × 544` 恒定尺寸，并将 `everythingFilterStrip` / `clipboardCategoryStrip` 移入左侧列表区内部，主分割线与顶部胶囊在 `全部 / 文件 / 剪贴板 / 插件` 四态切换时零位移、零跳动；
  - `AppViewModel` 通过后台 `Task.detached` 执行 `LauncherEngine.rankCandidates` 并发排序，`EverythingIndex` 增加空查询与扩展名分类快速路径，`VolumeInspector` 改用 `NSWorkspace` 挂载/卸载事件缓存，`IconCache` 缓存应用图标与按扩展名/目录复用的系统文件图标，`startPreview` 增加 `65ms` 防抖。
- **系统脉搏监控悬浮窗与菜单栏实时遥测（默认关闭 · 设置可配）**：
  - `SystemMonitorConfig` 将 `floatingEnabled` 与 `showInMenuBar` 新装默认值设为 `false`（零后台采样占用），并在设置中新增专门的 `系统监控` 页签（`TelemetrySettingsView`），可自由开关桌面悬浮窗、切换顶部精简/常驻/贴边自动隐藏、开关菜单栏读数并自选 `CPU / 频率 / 内存 / 功耗 / 网速` 显示项；
  - `SystemMonitorSampler` 通过 Mach/IOKit/`getifaddrs` 实时采集 CPU 总占比与 P/E 簇负载、硬件 DVFS 等效频率 (`GHz`)、GPU 利用率、物理内存/压缩内存/Swap、实时整机功耗 (`W`)、网络 `↑/↓` 速率与磁盘可用空间；
  - `SystemPulseWindowController` 与 `SystemPulseOverlayView` 提供顶部精简胶囊（悬停或点击向下展开 4 卡片实时趋势面板）、拖至屏幕左/右/上边缘自动贴边隐藏与悬停滑出，以及菜单栏等宽紧凑读数开关。
- **QQ 式原生截图标注、钉图与极速识字引擎 (`⌥A` / `⌥O`)**：
  - 基于 `ScreenCaptureKit`（`SCShareableContent` + `SCScreenshotManager.captureImage`）与 `CGPreflightScreenCaptureAccess` 实现全屏冻结、窗口智能吸附、8 控制点选区缩放、放大镜 `#HEX` 像素取色（`C` 键复制）、实时像素化马赛克预览、自动聚焦文字框、选中平移联动标注及鼠标右键快速清空/取消；
  - 通过隔离底层 `DragGesture` 避免拦截工具栏按钮点击；`⌥O` 识字模式框选或单击窗口松手即刻触发识别；
  - **修复 Vision 离线 OCR 卡死问题**：`VisionService` 显式将计算阶段绑定至 `MLComputeDevice.cpu`，消除 Apple Silicon Neural Engine ~36s 阻塞，实测亚秒级（~0.14s）完成中英混排 OCR 与条码扫描并弹出独立可编辑/合并换行的 `OCRResultWindowController` 窗口；
  - **重做悬浮钉图 (`PinInteractionLayer`)**：通过 AppKit `acceptsFirstMouse` + `window?.performDrag` 彻底修复钉图无法拖动问题，并新增鼠标滚轮缩放、`⌥+滚轮` 调透明度、悬停自动显隐操作条、右键功能菜单及 `Esc` 关闭。
- **LumakeyCore 核心引擎与 LumakeyMCP (`lumakey-mcp`)**：
  - `LauncherEngine`、`UnitAndCommandEngine`、`MosMouseService`、`MarkdownDocumentParser`、`MediaClassifier`、`ProcessSupervisor` + `MemoryStats`、`ClipboardMonitor`、`EverythingQuery`/`EverythingIndex`、`DirectoryScanner`、`BatchRenamePlanner`、`VolumeInspector`、`VisionService`、`PluginSystem` 及 stdio MCP 工具闭环。
- **Lumakey 原生界面与本机 `.dmg` 安装**：
  - `RoundedGlassContainerView` 9-slice `28pt` 连续圆角、Bento 控制中心、单一全搜框 + `Tab` 过滤、Mos 设置面板、独立销毁型 Markdown/文本/图片/视频阅读窗与全链路内存自洁；
  - `scripts/install-macos.sh` 支持一键构建 `dist/Lumakey.app`、打包 `dist/Lumakey.dmg` 并签名安装至 `/Applications/Lumakey.app`。

## 当前已知约束

- `LumakeyCheck` 覆盖全部 `LumakeyCore` 能力、Markdown 解析、统一全搜、`ProcessSupervisor` 同步/异步超时强杀、Mos 配置、`MemoryStats`、`ScreenshotCompositor` 合成与像素采样、GIF89a 流式编码、应用使用度排序、三层热键冲突检测、`.lumakeybackup` SHA-256 归档与本地 WebDAV 协议往返、Plugin v2 + DevToolkit + Snippets、以及真实 `lumakey-mcp` 子进程测试；GUI 交互、全局热键、真实 `ScreenCaptureKit` 屏幕录制弹窗与桌面滚轮拦截以实际运行验收为准；
- 初次使用 Mos 物理鼠标平滑与反转需授权「辅助功能」，初次使用原生截图标注与区域 GIF 录制需授权「屏幕录制」（均可在系统设置中一键跳转授权）。
