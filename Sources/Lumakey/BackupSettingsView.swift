import AppKit
import LumakeyCore
import SwiftUI

struct BackupSettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var state = BackupSettingsViewState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
            SettingsSectionHeroHeader(
                symbol: "externaldrive.fill.badge.icloud", topColor: .cyan, bottomColor: .indigo,
                title: "数据导出、本地备份与 WebDAV 云同步",
                subtitle: "一键归档全量配置、收藏剪贴板与外部插件包（SHA-256 完整性防篡改），密码仅存系统钥匙串。"
            ) {
                Button { state.exportLocalBackupInteractive(viewModel: viewModel) } label: {
                    Label("导出备份包", systemImage: "square.and.arrow.up.fill")
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true)).disabled(state.isBusy)
            }
            statusBannerSection
            if let pending = state.pendingRestore { restorePreviewCard(pending) }
            localArchiveCard
            webdavConfigCard
            remoteHistoryCard
            }
        }
        .onAppear { state.onAppearLoad() }
    }

    @ViewBuilder
    private var statusBannerSection: some View {
        if state.isBusy {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(state.busyLabel).font(.caption.weight(.medium)).foregroundStyle(LiquidColors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .liquidGlassCard(cornerRadius: LiquidRadii.row, solidReadable: true)
        } else if let banner = state.banner {
            let icon = banner.tone == .success ? "checkmark.seal.fill" : (banner.tone == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
            let tint: Color = banner.tone == .success ? .mint : (banner.tone == .error ? .orange : .cyan)
            HStack(spacing: 9) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(banner.message).font(.caption).foregroundStyle(LiquidColors.textPrimary)
                Spacer()
                Button { state.banner = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .liquidGlassCard(cornerRadius: LiquidRadii.row, solidReadable: true)
        }
    }

    private func restorePreviewCard(_ pending: PendingBackupRestore) -> some View {
        let s = pending.summary
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.mint)
                Text("恢复前快照核验：\(pending.sourceLabel)").font(.callout.weight(.bold))
                Spacer()
                Text("SHA-256 \(s.payloadSHA256.prefix(12))")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.mint)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.mint.opacity(0.14), in: Capsule())
            }
            Text("创建于 \(s.createdAtISO8601) · 来源主机 \(s.hostName) (v\(s.appVersion)) · 大小 \(FastFormatters.formatFileBytes(Int64(s.archiveByteCount)))")
                .font(.caption2).foregroundStyle(LiquidColors.textSecondary)

            HStack(spacing: 16) {
                Label("\(s.configCount) 项配置文件", systemImage: "slider.horizontal.3")
                Label("\(s.pinnedClipboardCount) 条收藏剪贴板", systemImage: "pin.fill")
                Label("\(s.pluginCount) 个外部插件", systemImage: "puzzlepiece.extension.fill")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary)

            HStack(spacing: 16) {
                Toggle("恢复配置", isOn: pendingOptionBinding(\.restoreConfigs))
                Toggle("恢复收藏剪贴板", isOn: pendingOptionBinding(\.restoreClipboard))
                Toggle("恢复外部插件包", isOn: pendingOptionBinding(\.restorePlugins))
                Spacer()
                Button("取消") { state.pendingRestore = nil }
                    .buttonStyle(GlassPillButtonStyle())
                Button("确认恢复此快照") { state.confirmPendingRestore(viewModel: viewModel) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
            .font(.caption)
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private var localArchiveCard: some View {
        HStack(alignment: .center, spacing: 12) {
            SquircleBadge(symbol: "archivebox.fill", topColor: .teal, bottomColor: .blue, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("本地 .lumakeybackup 快照归档").font(.callout.weight(.semibold)).lineLimit(1)
                Text("包含 Mos 滚轮、系统脉搏、热键/短语 JSON、收藏剪贴板（单图 ≤ 2MB 内嵌）与可执行插件。")
                    .font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)

            HStack(spacing: 8) {
                Button("打开配置目录") {
                    let dir = BackupArchiveService.defaultAppSupportDirectory()
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
                .buttonStyle(GlassPillButtonStyle())

                Button("从本地恢复…") { state.chooseLocalBackupForRestore() }
                    .buttonStyle(GlassPillButtonStyle()).disabled(state.isBusy)
                Button("导出本地备份包") { state.exportLocalBackupInteractive(viewModel: viewModel) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true)).disabled(state.isBusy)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private var webdavConfigCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("WebDAV 云端自动轮转同步", systemImage: "icloud.and.arrow.up.fill")
                    .font(.callout.weight(.semibold))
                Spacer()
                ForEach(WebDAVProviderPreset.allPresets) { preset in
                    let selected = state.selectedPresetID == preset.id
                    Button { state.selectPreset(preset) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: preset.symbol).font(.system(size: 10))
                            Text(preset.name).font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .foregroundStyle(selected ? Color.white : LiquidColors.textPrimary)
                        .background(selected ? Color.accentColor : LiquidColors.pillSurface, in: Capsule())
                        .overlay { Capsule().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(state.activePreset.setupHint)
                .font(.caption2).foregroundStyle(.cyan)

            GlassInputField(symbol: "link", placeholder: "WebDAV 地址，如 https://dav.jianguoyun.com/dav/", text: $state.webdavConfig.serverURL)

            HStack(spacing: 10) {
                GlassInputField(symbol: "person.fill", placeholder: "WebDAV 账号 / 邮箱", text: $state.webdavConfig.username)
                secureKeychainField
            }

            HStack(spacing: 12) {
                GlassInputField(symbol: "folder.fill", placeholder: "远端备份目录（默认 LumakeyBackups）", text: $state.webdavConfig.remoteDirectory)
                    .frame(maxWidth: 280)
                Stepper("保留最近 \(state.webdavConfig.keepLatestCount) 份", value: $state.webdavConfig.keepLatestCount, in: 1...50)
                    .font(.caption.monospacedDigit())
                Spacer()
                Toggle("启动时自动云备份", isOn: $state.webdavConfig.autoBackupOnLaunch)
                    .font(.caption)
            }

            HStack(spacing: 8) {
                Button("保存配置") {
                    if state.persistSettings() {
                        state.banner = BackupStatusBanner(tone: .success, message: "WebDAV 配置已保存，应用密码已加密存入系统钥匙串")
                    }
                }
                .buttonStyle(GlassPillButtonStyle())
                Button("测试连接") { state.runWebDAVTest() }
                    .buttonStyle(GlassPillButtonStyle())
                    .disabled(state.isBusy || !state.webdavConfig.isConfigured)
                Button("刷新云端列表") { state.refreshRemoteList() }
                    .buttonStyle(GlassPillButtonStyle())
                    .disabled(state.isBusy || !state.webdavConfig.isConfigured)
                Spacer()
                Button { state.uploadBackupToWebDAV(viewModel: viewModel) } label: {
                    Label("立即备份至 WebDAV", systemImage: "icloud.and.arrow.up")
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true))
                .disabled(state.isBusy || !state.webdavConfig.isConfigured)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private var secureKeychainField: some View {
        HStack(spacing: 7) {
            Image(systemName: "key.fill").font(.caption).foregroundStyle(.mint)
            SecureField("应用专用密码（仅存系统钥匙串）", text: $state.passwordInput)
                .textFieldStyle(.plain).font(.caption).foregroundStyle(LiquidColors.textPrimary)
            Text("Keychain").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.mint)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.mint.opacity(0.14), in: Capsule())
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(LiquidColors.inputFieldSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous).strokeBorder(LiquidColors.inputFieldBorder, lineWidth: 0.9) }
    }

    private var remoteHistoryCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("云端历史快照（\(state.remoteItems.count)）").font(.callout.weight(.semibold))
                Spacer()
                Text("自动轮转保留最新 \(state.webdavConfig.keepLatestCount) 份 .lumakeybackup")
                    .font(.caption2).foregroundStyle(LiquidColors.textSecondary)
            }
            if state.remoteItems.isEmpty {
                Text("暂无已加载的云端备份记录 · 配置 WebDAV 后点击「刷新云端列表」或「立即备份至 WebDAV」。")
                    .font(.caption2).foregroundStyle(LiquidColors.textSecondary).padding(.vertical, 6)
            } else {
                ForEach(state.remoteItems) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.zipper").foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.fileName).font(.caption.monospaced().weight(.semibold)).lineLimit(1)
                            Text("\(FastFormatters.formatModificationDate(item.sortDate)) · \(FastFormatters.formatFileBytes(item.sizeBytes))")
                                .font(.caption2).foregroundStyle(LiquidColors.textSecondary)
                        }
                        Spacer()
                        Button("从云端下载并恢复") { state.downloadAndStageRemoteRestore(item) }
                            .buttonStyle(GlassPillButtonStyle(prominent: true)).disabled(state.isBusy)
                        Button("删除") { state.deleteRemoteItem(item) }
                            .buttonStyle(GlassPillButtonStyle()).disabled(state.isBusy)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private func pendingOptionBinding(_ kp: WritableKeyPath<BackupRestoreOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { state.pendingRestore?.options[keyPath: kp] ?? true },
            set: { val in state.pendingRestore?.options[keyPath: kp] = val }
        )
    }
}
