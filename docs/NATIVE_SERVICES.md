# macOS 原生服务复用清单

`Lumakey` 坚持 **Native Services First** 原则：凡 macOS 14+ 原生框架与系统工具能够稳定提供的能力，一律直接复用，避免引入重型运行时或脆弱轮子。

| 能力领域 | 复用的 macOS 原生服务 / API | 说明与边界 |
| --- | --- | --- |
| 全局快捷键唤醒 | `Carbon` (`InstallEventHandler` + `RegisterEventHotKey`) | 在无边框 `.accessory` 菜单栏应用中可靠捕获 `⌥Space`、`⌥F`、`⌥C`、`⌥A`、`⌥O`、`⌥E`，无需辅助功能权限 |
| 真圆角背景折射与窗口拖拽 | `AppKit.NSVisualEffectView` (`maskImage` 9-slice) + `NSWindow.performDrag` | `28pt` 无缝背景折射、零方角外溢与全区拖拽 |
| 物理鼠标独立平滑 (内置 Mos) | `CoreGraphics.CGEvent.tapCreate` + `AXIsProcessTrustedWithOptions` + `CFRunLoopTimer` | 基于 `scrollWheelEventIsContinuous == 0` 精确区分外接鼠标与触控板；仅在启用 Mos 时请求辅助功能权限 |
| 内存计量与低开销回收 | `Darwin.task_info` (`TASK_VM_INFO`) + `malloc_zone_pressure_relief` + `DispatchSource.makeMemoryPressureSource` | 实时监控物理内存足迹并在空闲/系统内存紧张时主动归还自由堆页 |
| 有界子进程监管 | `Foundation.Process` + `DispatchWorkItem` + `SIGKILL` | 统一限定输出缓冲区与超时时间，窗口隐藏或退出即清理全部活跃子进程 |
| 系统资源、DVFS 频率与整机功耗监控 | `Darwin` (`host_processor_info` + `host_statistics64` + `getifaddrs` + `statfs`) + `IOKit` (`AppleSmartBattery`, `IOAccelerator`, `pmgr`) | 零子进程读取 CPU P/E 核负载、硬件频表等效频率、物理/压缩内存、实时功耗 (`W`) 与网速，并确定性释放 Mach VM 与 IOKit 对象 |
| Markdown / 文本独立渲染 | Swift 6 原生块级解析器 + `AttributedString(markdown:)` | 零 `WKWebView`、零额外 WebKit XPC 进程开销 |
| 单位与温度换算 | `Foundation.Measurement` (`UnitLength`, `UnitMass`, `UnitInformationStorage`, `UnitTemperature`) | 复用系统物理量转换模型 |
| 应用本地化与中文拼音检索 | `InfoPlist.loctable` + `String.applyingTransform(.toLatin)` | 直接解析系统包内中文名并用 ICU 音译为全拼与首字母 |
| 原生选区截图、标注与钉图置顶 | `ScreenCaptureKit` (`SCShareableContent` + `SCScreenshotManager`) + `CGPreflightScreenCaptureAccess` + `CGContext` | 免 CLI 毫秒级 Retina 冻屏、窗口识别吸附、像素取色、实时标注合成及原位悬浮钉图 (`level = .screenSaver` / `.floating`) |
| 离线文字/条码识别与抠图 | `Vision` (`VNRecognizeTextRequest`, `VNDetectBarcodesRequest`, `VNGenerateForegroundInstanceMaskRequest`) + `CoreML.MLComputeDevice.cpu` | 绑定 CPU 计算阶段避开部分系统环境下 Neural Engine ~36s 卡顿，实现亚秒级中英 OCR、条码识别与透明通道主体抠图 |
| 剪贴板监听与隐私排除 | `AppKit.NSPasteboard.general` (`changeCount` + `concealedTypes`) | 自动跳过密码管理器标记数据并在条目淘汰时删除对应缓存图片 |
| 端口、卷与多格式媒体预览 | `/usr/sbin/lsof` / `Darwin.statfs` / `ImageIO` / `AVKit.AVPlayerView` / `PDFKit` / `CryptoKit` | 硬件加速解码、无损看图与流式分块 SHA-256 |

## 选型红线

- 禁止将不受信任的输入拼入 `NSExpression(format:)` 进行表达式求值；数学解析采用纯 Swift 递归下降求值器。
- 禁止使用 `WKWebView` / `WebKit` 承担轻量文本或 Markdown 预览，确保常驻低内存足迹。
- 所有 `AVPlayer`、`CGEventTap`、`CFMachPort`、`NSEvent` 监听器、文件句柄与子进程必须在切换或销毁时确定性释放。
