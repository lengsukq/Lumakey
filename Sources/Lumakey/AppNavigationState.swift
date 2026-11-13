import Foundation
import SwiftUI
import LumakeyCore

extension OmniFilter {
    var symbolName: String {
        switch self {
        case .all: "sparkles"
        case .files: "magnifyingglass"
        case .clipboard: "doc.on.clipboard.fill"
        case .plugins: "puzzlepiece.extension.fill"
        }
    }

    var placeholder: String {
        switch self {
        case .all: "搜应用(拼音)、文件名、算式、ts/uuid/qr/;短语、gif、备份..."
        case .files: "仅搜索磁盘文件：ext:swift  pic:  video:  folder:  !tmp ..."
        case .clipboard: "仅搜索剪贴板历史（文本 / #色值 / 图片 / 文件）..."
        case .plugins: "筛选已启用扩展插件（支持 view 卡片与目录热重载）..."
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case monitor
    case network
    case cache
    case search
    case mos
    case clipboard
    case snippets
    case plugins
    case shortcuts
    case backup
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用与内存"
        case .monitor: "系统监控"
        case .network: "网络流量"
        case .cache: "应用缓存"
        case .search: "检索范围"
        case .mos: "Mos 鼠标"
        case .clipboard: "剪贴板隐私"
        case .snippets: "快捷短语"
        case .plugins: "插件与 MCP"
        case .shortcuts: "全局热键"
        case .backup: "导出与备份"
        case .about: "关于流光"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .monitor: "waveform.path.ecg"
        case .network: "network"
        case .cache: "internaldrive.fill"
        case .search: "magnifyingglass.circle.fill"
        case .mos: "computermouse.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .snippets: "text.quote"
        case .plugins: "puzzlepiece.extension.fill"
        case .shortcuts: "command.square.fill"
        case .backup: "externaldrive.badge.icloud"
        case .about: "sparkles"
        }
    }

    var badgeColors: (top: Color, bottom: Color) {
        switch self {
        case .general: (.cyan, .blue)
        case .monitor: (.mint, .cyan)
        case .network: (.cyan, .teal)
        case .cache: (.orange, .indigo)
        case .search: (.teal, .blue)
        case .mos: (.cyan, .indigo)
        case .clipboard: (.orange, .pink)
        case .snippets: (.cyan, .indigo)
        case .plugins: (.purple, .indigo)
        case .shortcuts: (.mint, .teal)
        case .backup: (.blue, .purple)
        case .about: (.indigo, .purple)
        }
    }
}

enum WindowRoute: Hashable {
    case welcome
    case workspace
    case networkMonitor
    case settings(SettingsSection)
    case documentReader(URL, [URL])
    case imageViewer(URL, [URL], Bool)
    case videoPlayer(URL, [URL], Bool)
}

enum EverythingScope: Hashable, Identifiable {
    case allVolumes
    case quickUserFolders
    case home
    case volume(name: String, mountPath: String)

    var id: String {
        switch self {
        case .allVolumes: "all"
        case .quickUserFolders: "quick"
        case .home: "home"
        case .volume(_, let path): "vol:\(path)"
        }
    }

    var title: String {
        switch self {
        case .allVolumes: "全盘 + 外置盘"
        case .quickUserFolders: "常用目录"
        case .home: "个人主目录"
        case .volume(let name, _): name
        }
    }

    func resolveRootURLs(volumes: [VolumeSummary] = VolumeInspector.externalVolumes()) -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        switch self {
        case .allVolumes:
            let externals = volumes.filter { $0.formatKind != .smb }.map { URL(fileURLWithPath: $0.mountPath) }
            return [home] + externals
        case .quickUserFolders:
            let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Desktop")
            let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Downloads")
            let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Documents")
            return [desktop, downloads, documents]
        case .home:
            return [home]
        case .volume(_, let mountPath):
            return [URL(fileURLWithPath: mountPath)]
        }
    }
}

struct WorkspaceTab: Identifiable, Hashable {
    let id: UUID
    var directoryURL: URL
    var filterText: String = ""

    init(id: UUID = UUID(), directoryURL: URL) {
        self.id = id
        self.directoryURL = directoryURL
    }

    var title: String {
        let name = directoryURL.lastPathComponent
        return name.isEmpty ? directoryURL.path : name
    }
}

struct PaneState {
    var tabs: [WorkspaceTab]
    var activeTabID: UUID
    var entries: [FileEntry] = [] {
        didSet { rebuildCategoryCounts() }
    }
    private(set) var categoryCounts: [WorkspaceMediaFilter: Int] = [.all: 0]
    var volumeSummary: VolumeSummary?
    var sortField: SortField = .name
    var sortOrder: LumakeySortOrder = .ascending
    var foldersFirst: Bool = true
    var mediaFilter: WorkspaceMediaFilter = .all
    var displayMode: WorkspaceDisplayMode = .list
    var showHidden: Bool = false
    var isScanning: Bool = false
    var history: [URL] = []
    var diagnostic: UserFacingDiagnostic?

    var activeTabIndex: Int {
        tabs.firstIndex(where: { $0.id == activeTabID }) ?? 0
    }

    var currentDirectory: URL {
        get { tabs[activeTabIndex].directoryURL }
        set { tabs[activeTabIndex].directoryURL = newValue }
    }

    var filterText: String {
        get { tabs[activeTabIndex].filterText }
        set { tabs[activeTabIndex].filterText = newValue }
    }

    var visibleEntries: [FileEntry] {
        let needle = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            guard mediaFilter.matches(entry) else { return false }
            guard !needle.isEmpty else { return true }
            return entry.name.localizedCaseInsensitiveContains(needle)
                || entry.extensionLowercased.localizedCaseInsensitiveContains(needle)
        }
    }

    func categoryCount(for filter: WorkspaceMediaFilter) -> Int {
        categoryCounts[filter, default: 0]
    }

    private mutating func rebuildCategoryCounts() {
        var counts: [WorkspaceMediaFilter: Int] = [.all: entries.count]
        for entry in entries {
            if entry.isDirectory && !entry.isPackage {
                counts[.folder, default: 0] += 1
                continue
            }
            switch entry.mediaKind {
            case .image: counts[.image, default: 0] += 1
            case .video: counts[.video, default: 0] += 1
            case .audio: counts[.audio, default: 0] += 1
            case .markdown, .text, .pdf: counts[.document, default: 0] += 1
            case .archive: counts[.archive, default: 0] += 1
            case .folder, .other: break
            }
        }
        categoryCounts = counts
    }
}

enum PreviewContentState {
    case empty
    case loading(FileEntry)
    case image(FileEntry, CGImage, CGSize?)
    case videoOrAudio(FileEntry)
    case pdf(FileEntry)
    case markdown(FileEntry, [MarkdownBlock], Bool)
    case text(FileEntry, String, Bool)
    case folderOrGeneric(FileEntry)
}
