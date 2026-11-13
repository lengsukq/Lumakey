# 流光 Lumakey

**专为 macOS Apple Silicon (`arm64`) 打造的原生 iOS 液态玻璃快捷效率中枢：菜单栏常驻、全局热键秒呼，以单一统一全搜栏整合应用、文件、剪贴板、计算、内置 Mos 鼠标平滑与 AI 插件，并配备零 WebKit 的 Markdown/文本/图像/视频独立阅读窗口与自动内存回收架构。**

`Lumakey` 是一个完全独立、零第三方依赖的 Swift 6 + SwiftUI/AppKit 原生桌面应用（`app.lumakey.macos`）。设计原则是：**优先复用 macOS 系统原生能力，保持干净可维护的 Clean Code，让高频效率指令零延迟触达且空闲占用极低。**

## 核心能力

- **单一统一全搜快捷中枢 (`⌥Space`) + 零抖动零动画切换 (`880 × 544` 恒定真圆角悬浮窗 + 高对比自适应排版)**：
  - 采用 AppKit `.popover` 自适应浅/深色 `9-slice NSVisualEffectView.maskImage` 严格裁剪 `28pt` 连续曲率大圆角，禁用搜索框模糊透明混叠（`CrispSearchTextField` + 动态高对比文字/边框令牌），保证浅色与深色壁纸下文字同样锐利清晰；
  - 主悬浮窗锁定 `880 × 544` 恒定尺寸，并将子过滤条移入左侧列表栏内部（主分割线不动、`Tab` 切换无动画），彻底消除在 `全部 / 文件 / 剪贴板 / 插件` 间切换时的窗口伸缩与画面跳动；
  - `LauncherEngine` 检索转入后台线程并发排序，配合 `IconCache`、`EverythingIndex` 空查询快速路径、缓存挂载卷与 `65ms` 预览防抖实现丝滑输入与切换。
  - **一个搜索栏搜遍一切（应用智能排序 + 全盘 Everything 秒搜 + 离线开发工具箱）**：基于前台活跃时长/频次 `log2` 加权、近度衰减与图钉常驻智能排序常用应用；默认即开启 `全盘 + 外置盘` 索引作用域，单框同时支持汉字/拼音、算式/进制/单位换算、离线开发瑞士军刀（时间戳/UUID/随机密码/Base64/URL/JWT/JSON/MD5/SHA-256/`#HEX` 色板/高清二维码）、快捷短语（`;` 前缀）、端口占用、`mos`/`监控`/`备份`、全盘文件（免前缀）与剪贴板历史；支持 `Tab` 零抖动切换过滤及 `⌘1..9` 快选、`⌘C` 复制、`⌘Return` 次级动作。
- **自定义全局热键、插件系统 v2、本地备份 & 原生 WebDAV 云同步**：
  - 全部 10 项全局快捷键支持可视化按键录制与三层冲突检测（应用内/插件互斥、系统符号热键与 `Carbon` 第三方占用探测）；
  - 插件系统 v2 支持 `FSEvents` 目录热重载、可视化配置表单、4 款官方脚手架商店与 `mode: "view"` 液态玻璃结构化卡片渲染，配套 `lumakey-mcp` 服务；
  - 支持打包带顶层 SHA-256 完整性校验的 `.lumakeybackup` 归档（含配置、自定义插件与已收藏剪贴板条目），并通过 Keychain 存密 + 原生 RFC 4918 WebDAV 直连坚果云、Nextcloud、群晖 NAS 或 Alist 同步备份与一键恢复。
- **内置系统脉搏监控悬浮窗 (`⌥M`) & 多视图文件与外置磁盘工作台 (`⌥E`)**：
  - 基于 Darwin Mach、`IOKit` 与 `getifaddrs` 零子进程采样 CPU P/E 核负载、动态等效频率 (`GHz`)、GPU 利用率、内存/Swap、实时整机功耗 (`W`) 与网速（新装默认关闭，设置内可开启顶部精简胶囊、贴边隐藏与菜单栏指标）；
  - 按需工作台 (`⌥E`) 支持 6 种排序、7 类媒体胶囊、列表/异步缩略图网格/双列紧凑视图、右侧居中图文视频预览与只读 NTFS 护航。
- **QQ 式原生截图标注、零依赖区域 GIF 动图录制与极速识字引擎 (`⌥A` / `⌥G` / `⌥O`)**：
  - 基于 `ScreenCaptureKit` 实现毫秒级冻屏：支持窗口吸附、8 控制点缩放、放大镜取色（`C` 键复制 `#HEX`）、实时马赛克预览、自动聚焦文字批注、右键重选/退出，以及 **移动 / 矩形 / 椭圆 / 箭头 / 画笔 / 荧光笔 / 马赛克 / 序号 / 文字**、`⌘Z` 撤销、双击复制；
  - **原生区域 GIF 录制 (`⌥G`)**：复用 `ScreenCaptureKit` (`SCScreenshotManager`) + `ImageIO` 流式 GIF89a 编码（无需安装 `ffmpeg`），配备灵动岛悬浮录制条、640p/960p/HD 分辨率缩放与静止帧合并压缩，录完自动双格式写入剪贴板并支持复制、另存为、访达定位与预览；
  - **交互式悬浮钉图 & 亚秒级离线 Vision OCR**：支持全图拖动、滚轮缩放、`⌥+滚轮` 透明度调节与右键菜单；绑定 CPU 计算设备彻底消除 Neural Engine 卡顿，框选松手即自动识字并弹出独立识字结果窗。
- **内置 Mos 鼠标平滑与滚轮方向增强 (`MosEngine`)**：
  - 基于 `CGEvent.tapCreate` 区分物理鼠标滚轮（`scrollWheelEventIsContinuous == 0`），**绝不影响触控板自然滚动**；支持滚轮方向反转、120Hz 高帧率像素级平滑插值、`⇧` 横向滚动、`⌥` 3× 加速、应用 Bundle ID 排除列表；关闭或静止时 0 后台消耗。
- **独立销毁型 Markdown / 文本 / 图像 / 视频窗口**：
  - **网络流量与去向监控 (`⌥N`) & 应用缓存管理**：无需 Root 权限的 `/usr/bin/nettop` 实时进程级 `↓/↑` 速率、累计流量、PID/应用图标、Socket 远程 `IP:port` / 接口 / 状态 / 反向 DNS 去向追踪（关闭窗口 0% CPU）；配套独立 **应用缓存管理页**，按桶统计并按需安全清理剪贴板图片、截图临时文件、Vision 抠图、影院转封装与内存索引，同时严格保护置顶文件与 `~/Library/Application Support/Lumakey` 配置目录。
  - **独立窗口阅读、图片/视频置顶 & 同目录视频播放列表**：
    - 纯 Swift `MarkdownDocumentParser` + `DocumentReaderWindowView`（**零 `WKWebView` 进程开销**），支持源码/渲染视图切换、同目录上下篇与窗口置顶；
    - 图片看图窗、OCR 窗、阅读器、影院播放器与文件工作台均集成 `WindowLevelStore`（**图片置顶 / 视频置顶 / 小窗置顶**）；
    - **4K 影院播放器**：通过序列化 `Hev1ResourceLoader` 修复 macOS 不识别 `'hev1'` 4K HEVC MP4 导致“有声无画”或卡顿问题，支持 **同目录视频播放列表与搜索过滤、`连播` 自动切集、小窗浮层、暗黑自动隐藏 HUD** 与 IINA 直达。
  - **大圆角毛玻璃统一视效**：真 `NSVisualEffectView` + `.ultraThinMaterial` 半透明底板、同心圆角搜索栏与垂直水平居中的 `76pt` Bento 卡片（`44pt` `0.32×` 超椭圆徽章匹配 `22pt` 卡片圆角）。
- **智能程序坞 (Dock) 驻留 & 稳定签名升级**：
  - 打开工作台、影院播放、阅读器或设置等独立窗口时自动在程序坞显示图标支持 `⌘Tab` 切换、最小化还原与右键窗口菜单，关闭所有标准窗口后自动恢复轻量菜单栏驻留（也可在设置固定常驻）。
  - 执行 `bash scripts/setup-local-signing.sh`（首次）可生成 10 年期本地受信任签名证书，后续 `bash scripts/install-macos.sh` 均原位更新，免除每次更新重授「辅助功能 / 屏幕录制」权限。
- **最优内存与子进程自洁架构 (`ProcessSupervisor` & `MemoryStats`)**：
  - 全部外部子进程通过 `ProcessSupervisor` 托管（8s 超时强杀 + 64 KB 有界读取 + 隐藏/退出即 `terminateAll()`）；
  - 浮窗隐藏 `30s` 自动销毁 `NSPanel` 与视图树，文件索引空闲 `90s` 或收到系统 `DispatchSource.makeMemoryPressureSource` 内存告警时自动释放并调用 `malloc_zone_pressure_relief` 归还堆页；剪贴板淘汰与钉图关闭时同步清理临时 PNG；双栏文件台按需打开、关闭即释放。
- **离线 Vision (`⌥O`) / 双栏文件与 NTFS 附加工作台 (`⌥E`) & MCP (`lumakey-mcp`)**：
  - 复用 Apple `Vision` 离线 OCR 与主体抠图、`Darwin.statfs` 只读 NTFS 护航，以及供 AI 助手生成/校验/测试脚本插件的 `lumakey-mcp` 服务。

## 明确的产品界限

- **以快捷工具为核心，文件管理作为按需附加工具**：主入口是快捷键唤起的悬浮控制面板，不强制打开占满屏幕的大窗口。
- **不做图像编辑与视频剪辑**：仅提供无损只读看图与影院级视频播放。
- **不做常驻后台全盘数据库守护进程**：不部署 `launchd` 常驻后台建库服务，索引仅在活跃窗口或有界内存中按需驻留并在空闲时自动卸载。
- **只支持 Apple Silicon (`arm64`) / macOS 14+**：构建与校验脚本显式拒绝 `x86_64` 与 Rosetta 转译环境。

## 快速开始

```bash
# 1. 文档与链接自检
python3 -B scripts/check-docs.py

# 2. 代码规范（<=300行/文件）、编译、单测与 MCP 真实子进程联调校验
bash scripts/verify-macos.sh

# 3. 构建独立 macOS arm64 .app 产物 (dist/Lumakey.app，含 AppIcon.icns)
bash scripts/build-macos.sh

# 4. 打包 dist/Lumakey.dmg 并安装到本机 /Applications/Lumakey.app
bash scripts/install-macos.sh
```

更多说明请从 [文档总览](docs/INDEX.md) 开始。
