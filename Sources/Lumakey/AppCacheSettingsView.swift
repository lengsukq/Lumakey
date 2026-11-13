import AppKit
import LumakeyCore
import SwiftUI

@MainActor
final class AppCacheViewState: ObservableObject {
    @Published var overview = AppCacheOverview(buckets: [], purgeableBytes: 0, protectedBytes: 0, residentMemoryMB: 0)
    @Published var statusBanner: String?

    func refresh(viewModel: AppViewModel) {
        let residentNodes = viewModel.residentEverythingNodeCount
        let memoryEst = Int64(residentNodes * MemoryLayout<IndexedNode>.stride)
        overview = AppCacheService.inspectAll(
            inMemoryEstimatedBytes: memoryEst,
            inMemoryItemCount: residentNodes + viewModel.clipboardHistoryCount
        )
    }

    func protectedURLs(from viewModel: AppViewModel) -> Set<URL> {
        var set = Set(viewModel.clipboardItems.filter(\.isPinned).compactMap(\.fileURL))
        if let capture = viewModel.latestCaptureURL { set.insert(capture) }
        return set
    }

    func clearBucket(_ bucket: AppCacheBucketReport, viewModel: AppViewModel) {
        let protected = protectedURLs(from: viewModel)
        let freed = AppCacheService.clearBucket(bucket.kind, protectedURLs: protected) {
            viewModel.reclaimAllIdleMemoryNow()
        }
        if bucket.kind == .clipboardImages {
            viewModel.clearUnpinnedClipboard()
        }
        statusBanner = bucket.kind == .inMemoryIndexes
            ? "已回收空闲索引与可释放堆内存"
            : "已清理 \(bucket.title)：释放 \(NetworkTrafficParser.formatBytes(freed))"
        refresh(viewModel: viewModel)
    }

    func clearAll(viewModel: AppViewModel) {
        let protected = protectedURLs(from: viewModel)
        let freed = AppCacheService.clearAllPurgeable(protectedURLs: protected) {
            viewModel.reclaimAllIdleMemoryNow()
        }
        viewModel.clearUnpinnedClipboard()
        statusBanner = "一键清理完成：共释放磁盘缓存 \(NetworkTrafficParser.formatBytes(freed)) 并触发内存压缩"
        refresh(viewModel: viewModel)
    }
}

struct AppCacheSettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var cacheState = AppCacheViewState()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSectionHeroHeader(
                symbol: "internaldrive.fill",
                topColor: .orange,
                bottomColor: .indigo,
                title: "应用缓存与存储管理",
                subtitle: "分类统计 Lumakey 临时缓存（剪贴板图片、钉图、抠图、影院转封装），配置与插件受保护不会被误删。"
            ) {
                HStack(spacing: 8) {
                    Button { cacheState.refresh(viewModel: viewModel) } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GlassPillButtonStyle())

                    Button { cacheState.clearAll(viewModel: viewModel) } label: {
                        Label("一键清理全部缓存", systemImage: "trash.fill")
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                }
            }

            summaryCard

            if let banner = cacheState.statusBanner {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint)
                    Text(banner).font(.caption).foregroundStyle(LiquidColors.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .liquidGlassCard(cornerRadius: LiquidRadii.row)
            }

            VStack(spacing: 8) {
                ForEach(cacheState.overview.buckets) { bucket in
                    bucketCard(bucket)
                }
            }
        }
        .onAppear { cacheState.refresh(viewModel: viewModel) }
    }

    private var summaryCard: some View {
        HStack(alignment: .center, spacing: 14) {
            kpiStat(title: "可清理磁盘缓存", value: NetworkTrafficParser.formatBytes(cacheState.overview.purgeableBytes), color: .orange)
            Divider().frame(height: 30).opacity(0.25)
            kpiStat(title: "配置与插件（受保护）", value: NetworkTrafficParser.formatBytes(cacheState.overview.protectedBytes), color: .cyan)
            Divider().frame(height: 30).opacity(0.25)
            kpiStat(title: "当前常驻内存", value: String(format: "%.1f MB", cacheState.overview.residentMemoryMB), color: .mint)
            Spacer()
            Button("回收空闲内存") {
                viewModel.reclaimAllIdleMemoryNow()
                cacheState.refresh(viewModel: viewModel)
            }
            .buttonStyle(GlassPillButtonStyle())
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .liquidGlassCard(cornerRadius: LiquidRadii.card)
    }

    private func bucketCard(_ bucket: AppCacheBucketReport) -> some View {
        let icon = bucketVisual(bucket.kind)
        return HStack(alignment: .center, spacing: 14) {
            SquircleBadge(symbol: icon.symbol, topColor: icon.top, bottomColor: icon.bottom, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(bucket.title).font(.callout.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary)
                    if bucket.isProtected {
                        Text("受保护").font(.system(size: 10, weight: .semibold)).foregroundStyle(.cyan)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.14), in: Capsule())
                    }
                }
                Text(bucket.subtitle).font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(bucket.kind == .inMemoryIndexes ? "\(bucket.fileCount) 索引项" : "\(bucket.fileCount) 文件")
                    .font(.caption2.monospacedDigit()).foregroundStyle(LiquidColors.textSecondary)
                Text(NetworkTrafficParser.formatBytes(bucket.sizeBytes))
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(LiquidColors.textPrimary)
            }
            if let dirURL = bucket.locationURL, FileManager.default.fileExists(atPath: dirURL.path) {
                Button("访达") { NSWorkspace.shared.activateFileViewerSelecting([dirURL]) }
                    .buttonStyle(GlassPillButtonStyle())
            }
            if !bucket.isProtected {
                Button(bucket.kind == .inMemoryIndexes ? "释放" : "清理") {
                    cacheState.clearBucket(bucket, viewModel: viewModel)
                }
                .buttonStyle(GlassPillButtonStyle())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .liquidGlassCard(cornerRadius: LiquidRadii.card)
    }

    private func kpiStat(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.caption2).foregroundStyle(LiquidColors.textSecondary)
            }
            Text(value).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(LiquidColors.textPrimary)
        }
    }

    private func bucketVisual(_ kind: AppCacheBucketKind) -> (symbol: String, top: Color, bottom: Color) {
        switch kind {
        case .clipboardImages: ("doc.on.clipboard.fill", .orange, .pink)
        case .screenshotsAndPins: ("camera.viewfinder", .mint, .teal)
        case .visionCutouts: ("wand.and.stars", .purple, .indigo)
        case .cinemaRemux: ("film.fill", .cyan, .blue)
        case .diskIndexSnapshot: ("internaldrive.fill", .blue, .teal)
        case .inMemoryIndexes: ("memorychip", .teal, .mint)
        case .appSupportConfig: ("lock.shield.fill", .indigo, .blue)
        }
    }
}
