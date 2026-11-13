# Everything 检索引擎设计

为在 macOS 上获得类似 Windows Everything 的即时筛选手感，`Lumakey` 采用**多根目录内存紧凑父指针树 (`EverythingIndex`) + 查询 DSL 解析器 (`EverythingQuery`)**。

## 内存结构设计

传统文件树为每个节点保存完整绝对路径会成倍放大堆内存与字符串分配开销。`LumakeyCore` 采用平坦数组存储，并通过 `rootIndex` 默认同时索引本机主目录与全部已挂载外置磁盘（`EverythingScope.allVolumes`，亦可一键切换至常用目录或单一卷）：

```swift
public struct IndexedNode: Sendable, Hashable {
    public let parentID: Int32 // 根节点直接子项为 -1
    public let rootIndex: UInt16
    public let isDirectory: Bool
    public let name: String
}
```

- **POSIX 零 stat 扫描 + 零冗余分配匹配**：`EverythingIndex.build` 直接调用 `Darwin.opendir`/`readdir` 并利用 `d_type` 判别目录（免去外置 FUSE/NTFS 大盘上万次同步 `stat` RPC），采用 `24 B` 紧凑 `IndexedNode`（去除全量小写/扩展名副本与无效字段），查询期由 `QueryNeedle` 对 `name` 执行原地 UTF-8 大小写折叠匹配并在 Top N 命中时按需 `stat` 补齐文件大小、修改时间与卷前缀路径。
- **确定性有界遍历**：默认跳过 `Library`、`node_modules`、`.git`、`.build`、`DerivedData`、`Caches`、`.Spotlight-V100`、`.Trashes`、`$RECYCLE.BIN` 与 `.venv` 等缓存目录，设置节点上限并在 `Task.isCancelled` 时协作退出。

## 查询 DSL 语法

`EverythingQuery` 将用户输入的查询串解析为**若干 OR (`|`) 子句，每个子句包含若干 AND 词项**：

| 语法词项 | 含义与示例 |
| --- | --- |
| 普通关键词 | 大小写不敏感文件名匹配，如 `report 2026` |
| `ext:a;b;c` | 扩展名集合匹配，如 `ext:swift;md` 或 `ext:mp4;mkv` |
| `folder:` | 仅匹配文件夹 |
| `file:` | 仅匹配普通文件 |
| `video:` | 视频扩展名预设 (`mp4/mov/m4v/mkv/avi/webm/ts/flv`) |
| `pic:` | 图片扩展名预设 (`png/jpg/jpeg/webp/heic/gif/tiff/bmp/raw/dng`) |
| `path:substr` | 父目录路径子串匹配（触发时按需解析父路径） |
| `!term` | 逻辑取反排除条件，可与上述任意词项组合，如 `!ext:tmp !.git` |
| `A \| B` | 多组条件“或”连接，如 `ext:png \| ext:jpg` |

## 持久化二进制快照与 FSEvents 增量同步

- **紧凑二进制快照与 O(1) 头部启动 (`EverythingSnapshotStore`)**：将 `IndexedNode` 父指针树以 `LMKYIDX2` 紧凑格式落盘至 `~/Library/Caches/com.queensu.lumakey/everything-index/idx-<sha256>.lmkyidx`（每节点仅 `9 B + UTF-8`）。冷启动仅通过 `readHeaderMetadata(...)` 读取前 4 KB 校验根目录与获取节点总数（实现启动期零内存索引驻留），仅在切入文件模式或输入搜索词时通过 `Data(contentsOf:options: .mappedIfSafe)` 恢复内存检索，闲置 `90s` 自动卸载。
- **macOS `FSEvents` 实时增量更新 (`EverythingFSEventWatcher` + `applyingFSEventDirectories`)**：针对本机与快速外置卷监听 `FSEventStreamCreate` 目录事件（`0.9s` 防抖），跳过易阻塞的慢速/FUSE/SMB 卷；增量重建时仅对变更目录及其新增子目录执行 POSIX `readdir`，其余未变分支零系统调用复用原节点并延迟写回快照。

## 在快捷台与独立模式中的集成

- **独立秒搜模式 (`⌥F`)**：打开后直接展示作用域与语法胶囊，并自动在右侧开启 `300pt` 侧边玻璃预览镜。
- **快捷台内联直达 (`⌥Space`)**：输入 `f `、`open `、`find ` 或任意 `ext:`/`pic:`/`video:`/`folder:`/`path:` DSL 时，可在主快捷台直接检索并打开命中文件。
- **工作台目录缓存协同**：文件工作台 (`⌥E`) 采用 `WorkspaceDirectoryCache` 48 项 LRU + SWR 异步刷新与 `IconCache` 扩展名图标复用；后续 [版本路线图](ROADMAP.md) M2 还可继续补充 `getattrlistbulk` 目录批读取优化。
