# AGENTS.md

本文件面向所有在本仓库工作的人类开发者与 AI 编码代理。

## 核心准则

1. **严格单一事实来源**：
   - 架构、规范、路线图和当前状态各归其位，不要制造带日期的重复报告文档。
   - 新增或重命名 `docs/` 下的文档时，必须同步更新 [docs/INDEX.md](docs/INDEX.md)。
   - 修改文档后必须执行 `python3 -B scripts/check-docs.py`，保持 `0 issue(s)`。
2. **严守 Clean Code 硬门槛**：
   - `Sources/` 下每个 `.swift` 文件必须职责单一，且行数严格 **<= 300 行**（由 `scripts/verify-macos.sh` 自动检查拦截）。
   - 不引入任何第三方 SwiftPM / CocoaPods 依赖。
   - 禁止重复逻辑、投机性预留死代码（`TODO`/未接入函数）与未清理的后台任务或播放器句柄。
   - 严禁向 `NSExpression(format:)` 传入未过滤用户输入，防止抛出 Swift `do/catch` 无法捕获的 Objective-C 异常崩溃。
3. **macOS 原生服务优先与产品边界**：
   - 截图、悬浮置顶、OCR、条码识别、抠图、缩略图、音视频与 PDF 预览必须优先复用系统框架（包括 `ScreenCaptureKit` 截图标注合成、`Vision` 与 `AVKit`）。
   - 严禁在文件工作台中加入图像/视频批量剪辑工程、后台常驻守护进程或破坏性的 NTFS 强行读写挂载逻辑。
   - `Lumakey` 是完全独立的桌面端，不依赖或耦合任何外部项目。
4. **如实记录实现状态**：
   - [docs/STATUS.md](docs/STATUS.md) 只记录已经通过编译与校验的真实能力，未实现的 M1/M2 功能归入 [docs/ROADMAP.md](docs/ROADMAP.md)。
   - 所有验证命令（`check-docs.py`、`verify-macos.sh`、`build-macos.sh`）必须在最终改动后真实运行通过后再汇报。
