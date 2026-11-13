# 本地开发与构建指南

## 环境要求

- **硬件与系统**：Apple Silicon (`arm64`) Mac，运行 `macOS 14.0+`。
- **工具链**：Apple Swift 6 工具链（Command Line Tools 或 Xcode 均可，`xcode-select -p` 无需完整 Xcode 即可编译全部目标）。
- **外部依赖**：**零第三方 Swift 包依赖**。如宿主机已通过 Homebrew 安装 `ntfs-3g` 或 `ffmpeg`/`ffprobe`，应用会自动探测其状态。

## 目录结构

```text
Lumakey/
├── Package.swift                 # Swift 6 四目标清单 (LumakeyCore / Lumakey / lumakey-mcp / LumakeyCheck)
├── apps/macos/Info.plist         # macOS arm64 应用包元数据 (app.lumakey.macos, LSUIElement = true)
├── Sources/
│   ├── LumakeyCore/              # 无 UI 强依赖的核心引擎与系统服务封装
│   ├── Lumakey/                  # SwiftUI + AppKit 菜单栏常驻与 iOS 液态玻璃界面
│   └── LumakeyMCP/               # 原生 stdio JSON-RPC 2.0 MCP 服务 (lumakey-mcp)
├── Tests/
│   └── LumakeyCheck/             # 确定性校验程序与 MCP 真实子进程测试
├── scripts/
│   ├── check-docs.py             # 文档索引覆盖与断链/锚点检查
│   ├── verify-macos.sh           # arm64 环境、300 行 Clean Code、编译与校验总门禁
│   ├── generate-icon.swift       # 生成 Retina iOS 液态玻璃 AppIcon 图标集
│   ├── build-macos.sh            # 构建 dist/Lumakey.app（含 AppIcon.icns）并执行临时签名
│   └── install-macos.sh          # 构建、封装 dist/Lumakey.dmg 并部署到 /Applications/Lumakey.app
└── docs/                         # 设计与工程文档
```

## 常用开发命令

```bash
# 校验全部文档与内部链接
python3 -B scripts/check-docs.py

# 执行完整静态检查、Clean Code 300 行检查、Swift 编译与测试集
bash scripts/verify-macos.sh

# 打包独立的 arm64 macOS 应用 (包含 Lumakey、lumakey-mcp 与 AppIcon.icns)
bash scripts/build-macos.sh

# 打包 .dmg 并安装到 /Applications/Lumakey.app
bash scripts/install-macos.sh

# 直接以 CLI 模式调试 MCP 服务器
swift run lumakey-mcp
```

打包完成后，应用包位于 `dist/Lumakey.app`，内部包含主执行文件 `dist/Lumakey.app/Contents/MacOS/Lumakey`、伴随 MCP 工具 `dist/Lumakey.app/Contents/MacOS/lumakey-mcp` 与图标资源 `dist/Lumakey.app/Contents/Resources/AppIcon.icns`。
