# 液态玻璃设计规范

`Lumakey` 采用融合 **iOS Control Center 与 macOS Liquid Glass** 的精致视觉语言：通过 AppKit 9-slice 真圆角穿透毛玻璃、无直角渗漏外框、连续曲率层次与克制的高光边界，让浮窗自然悬浮于桌面之上。

## 视觉层级与材质

1. **真圆角悬浮中枢外壳（`RoundedGlassContainerView` + `OverlayCommandView`）**：
   - AppKit 层 `RoundedGlassContainerView` 继承 `NSVisualEffectView`（`.popover` + `.behindWindow` + `.active`），生成 `28pt` 连续圆角 9-slice `maskImage` 并配合 `.cornerCurve = .continuous` 图层裁剪；配合 `LiquidColors.shellTint` / `inputFieldSurface` / `textPrimary` 高对比动态令牌与 `CrispSearchTextField`（`allowsVibrancy = false`），浅色/深色壁纸下文字、占位符与按钮均保持清晰可读；
   - 顶部提供 `18pt` 极简抓手条（拖拽移窗，双击居中重置位置），搜索栏外边距、Bento 空白区、底栏空闲区及 `⌘`+左键全区域均可流畅拖动；面板锁定 **`880 × 544` 恒定零跳动尺寸**，文件与剪贴板子过滤条内嵌于左侧列表区顶部，`全部 / 文件 / 剪贴板 / 插件` 四态切换时外框与主分割线完全静止。
   - 系统脉搏监控悬浮窗采用与主面板同源的 `20pt` `.popover` 液态玻璃胶囊，支持顶部精简横条悬停展开、三边吸附隐藏标签及高对比等宽 Sparkline 卡片；截图标注浮层采用全屏 `.screenSaver` 无边框透明层 + `Canvas` 矢量渲染 + 底部两行 iOS 液态玻璃浮动工具条 + 像素放大镜取色框。
2. **Bento 磁贴、胶囊与高光超椭圆徽章**：
   - 控制中心 `3×2` Bento 磁贴与 8 格应用坞采用 `22pt` 连续圆角 `.ultraThinMaterial` + 柔和白边（`softCardRimGradient`）；
   - 功能图标统一使用 `SquircleBadge`（`size * 0.28` 连续圆角、线性渐变、顶部白色镜面高光与柔和投影）；
   - 主搜索框、四态过滤胶囊（`全部` / `文件` / `剪贴板` / `插件`）、操作按钮与按键提示（`KeycapPill`）均采用 `Capsule(style: .continuous)` 全圆角。
3. **独立阅读窗与高密度内容层**：
   - Markdown 阅读窗口与侧边预览文本使用 `solidReadable` 高对比可读玻璃表面，配合 `MarkdownBlocksView` 呈现代码框、引用左竖线、Callout 徽标与紧凑 GFM 表格。

## 圆角规范（Apple `.continuous` 连续曲率）

| 元素 | 圆角令牌 | 数值 |
| --- | --- | --- |
| 主悬浮快捷面板外壳（9-slice `maskImage` + 图层裁剪） | `LiquidRadii.panel` | `28pt` |
| 独立窗口主区域 / 钉图浮窗 | `LiquidRadii.windowPanel` / 钉图 | `24pt` / `20pt` |
| iOS Bento 磁贴 / 应用坞 / 设置分组 | `LiquidRadii.bento` | `22pt` |
| 通用玻璃卡片 / 侧边预览区 | `LiquidRadii.card` | `18pt` |
| 键盘流高亮选中行 | `LiquidRadii.row` | `15pt` |
| 内部预览子卡片 / 代码块 / Callout | `LiquidRadii.control` | `12pt` |
| 搜索栏、四态胶囊、按钮、快捷键提示 | `Capsule(style: .continuous)` | 全圆角 |

## 色彩与可访问性降级

- 全部颜色令牌通过 `NSColor(name:dynamicProvider:)` 动态响应 macOS 浅色与深色模式，禁止硬编码孤立色彩。
- 当系统开启 `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` 时，自动将窗口与卡片玻璃材质切换为高不透明度纯色表面；
- 当开启 `accessibilityDisplayShouldIncreaseContrast` 时，自动增强玻璃描边线宽与边框不透明度。
