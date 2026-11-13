# macOS 原生服务复用清单

`Lumakey` 坚持 **Native Services First** 原则：凡 macOS 14+ 原生框架与系统工具能够稳定提供的能力，一律直接复用，避免引入重型运行时或脆弱轮子。

| 能力领域 | 复用的 macOS 原生服务 / API | 说明与边界 |
| --- | --- | --- |
| 全局快捷键唤醒与三层冲突检测 | `Carbon` (`InstallEventHandler` + `RegisterEventHotKey`) + `com.apple.symbolichotkeys` | 在无边框 `.accessory` 应用中可靠捕获 10 项自定义全局热键，并在录制时探测应用内、系统符号热键与第三方 Carbon 占用，无需辅助功能权限 |
| 真圆角背景折射与无障碍自适应 | `AppKit.NSVisualEffectView` (`maskImage` 9-slice) + `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` | `28pt` 无缝背景折射、零方角外溢、全区拖拽与 O(1) 事件驱动无障碍减透/高对比度降级 |
| 应用使用度冷启动探测与活跃追踪 | `CoreServices.MDItem` (`kMDItemUseCount` / `kMDItemLastUsedDate`) + `NSWorkspace` 前台激活通知 | 零隐私侵入融合系统 Spotlight 启动计数、Dock 常用栏与前台活跃时长，驱动智能排序与常驻钉选 |
| 物理鼠标独立平滑 (内置 Mos) | `CoreGraphics.CGEvent.tapCreate` + `AXIsProcessTrustedWithOptions` + `CFRunLoopTimer` | 基于 `scrollWheelEventIsContinuous == 0` 精确区分外接鼠标与触控板；仅在启用 Mos 时请求辅助功能权限 |
| 内存计量与低开销回收 | `Darwin.task_info` (`TASK_VM_INFO`) + `malloc_zone_pressure_relief` + `DispatchSource.makeMemoryPressureSource` | 实时监控物理内存足迹并在空闲/系统内存紧张时主动归还自由堆页 |
| 有界子进程监管 | `Foundation.Process` + `DispatchWorkItem` + `SIGKILL` | 同步/异步统一限定输出缓冲区与超时时间，窗口隐藏或退出即清理全部活跃子进程 |
| 系统资源、DVFS 频率与整机功耗监控 | `Darwin` (`host_processor_info` + `host_statistics64` + `getifaddrs` + `statfs`) + `IOKit` (`AppleSmartBattery`, `IOAccelerator`, `pmgr`) | 零子进程读取 CPU P/E 核负载、硬件频表等效频率、物理/压缩内存、实时功耗 (`W`) 与网速，并确定性释放 Mach VM 与 IOKit 对象 |
| Markdown / 文本独立渲染 | Swift 6 原生块级解析器 + `AttributedString(markdown:)` | 零 `WKWebView`、零额外 WebKit XPC 进程开销 |
| 单位换算、密码学哈希与二维码生成 | `Foundation.Measurement` + `CryptoKit` (`Insecure.MD5`, `SHA1`, `SHA256`, `SHA512`) + `CoreImage` (`CIQRCodeGenerator`) | 离线秒算物理量换算、多算法摘要与高清无锯齿矢量缩放二维码 PNG |
| 应用本地化与中文拼音检索 | `InfoPlist.loctable` + `String.applyingTransform(.toLatin)` | 直接解析系统包内中文名并用 ICU 音译为全拼与首字母 |
| 原生选区截图、标注与钉图置顶 | `ScreenCaptureKit` (`SCShareableContent` + `SCScreenshotManager`) + `CGPreflightScreenCaptureAccess` + `CGContext` | 免 CLI 毫秒级 Retina 冻屏、窗口识别吸附、像素取色、实时标注合成及原位悬浮钉图 (`level = .screenSaver` / `.floating`) |
| 原生区域 GIF 动图流式录制 | `ScreenCaptureKit` (`SCStream`) + `ImageIO` (`CGImageDestination` `com.compuserve.gif`) | 零 `ffmpeg` 依赖实现区域帧流采集、Retina 1x 降采样、静止帧差值合并与双格式剪贴板输出 |
| 离线文字/条码识别与抠图 | `Vision` (`VNRecognizeTextRequest`, `VNDetectBarcodesRequest`, `VNGenerateForegroundInstanceMaskRequest`) + `CoreML.MLComputeDevice.cpu` | 绑定 CPU 计算阶段避开部分系统环境下 Neural Engine ~36s 卡顿，实现亚秒级中英 OCR、条码识别与透明通道主体抠图 |
| 本地完整性备份与 WebDAV 云同步 | `CryptoKit.SHA256` + `Security` (`SecItemAdd` / `SecItemCopyMatching`) + `Foundation.URLSession` (RFC 4918) | 生成带 SHA-256 清单的 `.lumakeybackup` 归档，钥匙串安全存密并原生直连坚果云/Nextcloud/群晖 WebDAV |
| 剪贴板监听与隐私排除 | `AppKit.NSPasteboard.general` (`changeCount` + `concealedTypes`) | 自动跳过密码管理器标记数据并在条目淘汰时删除对应缓存图片 |
| 端口、文件事件、卷与多格式媒体预览 | `/usr/sbin/lsof` / `CoreServices.FSEventStream` / `Darwin.statfs` / `ImageIO` / `AVKit.AVPlayerView` / `PDFKit` | 文件索引与插件目录实时增量监听、硬件加速解码与无损看图 |

## 选型红线

- 禁止将不受信任的输入拼入 `NSExpression(format:)` 进行表达式求值；数学解析采用纯 Swift 递归下降求值器。
- 禁止使用 `WKWebView` / `WebKit` 承担轻量文本或 Markdown 预览，确保常驻低内存足迹。
- 所有 `AVPlayer`、`CGEventTap`、`CFMachPort`、`NSEvent` 监听器、文件句柄与子进程必须在切换或销毁时确定性释放。
