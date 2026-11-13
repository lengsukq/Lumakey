import AppKit
import LumakeyCore
import SwiftUI

struct SettingsDetailSectionsView: View {
    @ObservedObject var viewModel: AppViewModel
    let section: SettingsSection

    var body: some View {
        switch section {
        case .search: searchSection
        case .clipboard: clipboardSection
        case .plugins: pluginsSection
        case .shortcuts: shortcutsSection
        case .about: aboutSection
        default: EmptyView()
        }
    }

    private var searchSection: some View {
        let dslExamples: [(token: String, desc: String)] = [
            ("ext:swift;md", "同时按多个扩展名精确过滤"),
            ("pic:", "一键列出全盘与外置盘图片"),
            ("video:", "快速查找视频与影片文件"),
            ("folder:", "仅筛选目录文件夹（排除普通文件）"),
            ("path:lightlsle", "限制在包含指定目录或卷名下检索"),
            ("report !tmp | ext:pdf", "空格表“与”、!表“排除”、|表“或”")
        ]
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeroHeader(
                    symbol: "magnifyingglass.circle.fill", topColor: .teal, bottomColor: .blue,
                    title: "Everything 检索引擎与范围",
                    subtitle: "基于 POSIX opendir/readdir 与多卷轮询队列，开箱自动索引本机主目录与全部已挂载外置磁盘。"
                ) {
                    Text(viewModel.isIndexingEverything ? "索引中…" : "\(viewModel.everythingNodeCount) 节点")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("默认检索作用域（点击即刻切换并重建）").font(.callout.weight(.semibold))
                        Spacer()
                        Button("重建磁盘缓存") { viewModel.forceRebuildEverythingIndex() }
                            .buttonStyle(GlassPillButtonStyle())
                        Button("立即呼出搜文件 (⌥F)") { viewModel.showOverlay(filter: .files) }
                            .buttonStyle(GlassPillButtonStyle(prominent: true))
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 8)], spacing: 8) {
                        ForEach(viewModel.availableEverythingScopes) { scope in
                            let active = viewModel.everythingScope == scope
                            Button { viewModel.rebuildEverythingIndex(scope: scope) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: scopeIcon(scope))
                                        .foregroundStyle(active ? Color.white : .cyan)
                                    Text(scope.title).font(.caption.weight(.semibold)).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .foregroundStyle(active ? Color.white : LiquidColors.textPrimary)
                                .background(active ? Color.accentColor : LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14).liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Everything 查询语法速查（点击自动填入搜索框试用）").font(.callout.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(dslExamples, id: \.token) { item in
                            Button {
                                viewModel.overlayQuery = item.token
                                viewModel.showOverlay(filter: .files)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.token).font(.caption.monospaced().weight(.bold)).foregroundStyle(.cyan)
                                    Text(item.desc).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14).liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
            }
        }
    }

    private func scopeIcon(_ scope: EverythingScope) -> String {
        switch scope {
        case .allVolumes: "externaldrive.fill.badge.checkmark"
        case .quickUserFolders: "folder.fill"
        case .home: "house.fill"
        case .volume: "externaldrive.fill"
        }
    }

    private var clipboardSection: some View {
        let pinnedCount = viewModel.clipboardItems.filter(\.isPinned).count
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeroHeader(
                    symbol: "doc.on.clipboard.fill", topColor: .orange, bottomColor: .pink,
                    title: "智能剪贴板库与隐私防护",
                    subtitle: "本地内存与有界临时文件储存，退出或清空即同步回收 PNG 缓存，绝不上传云端。"
                ) {
                    Button("打开剪贴板 (⌥C)") { viewModel.showOverlay(filter: .clipboard) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                }

                HStack(spacing: 10) {
                    statBox("当前历史条目", value: "\(viewModel.clipboardItems.count) 条", sub: "未收藏上限 80 条", tint: .orange)
                    statBox("永久收藏条目", value: "\(pinnedCount) 条", sub: "不受 FIFO 淘汰清理", tint: .pink)
                    statBox("隐私过滤模式", value: "已启用", sub: "自动绕过密码管理器", tint: .green)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("安全采集与内存回收机制").font(.callout.weight(.semibold))
                    privacyRuleRow("lock.shield.fill", .green, "自动过滤密码管理器敏感内容", "遇到 org.nspasteboard.ConcealedType、TransientType 或 1Password 复制项立即跳过记录。")
                    privacyRuleRow("paintpalette.fill", .purple, "支持文本、#HEX 色块、图片与文件路径", "识别颜色值后可直接在右侧预览色块并一键复制。")
                    privacyRuleRow("trash.circle.fill", .orange, "临时图片引用随记录淘汰自动删除", "点击“清空未收藏条目”会同时从磁盘删除对应剪贴板临时 PNG。")
                }
                .padding(14).liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)

                HStack(spacing: 10) {
                    Button("清空未收藏条目") { viewModel.clearUnpinnedClipboard() }
                        .buttonStyle(GlassPillButtonStyle())
                    Button("清空全部剪贴板") { viewModel.clipboardItems.removeAll() }
                        .buttonStyle(GlassPillButtonStyle())
                }
            }
        }
    }

    private func statBox(_ title: String, value: String, sub: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(tint)
            Text(sub).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }

    private func privacyRuleRow(_ symbol: String, _ color: Color, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                Text(desc).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
    }

    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeroHeader(
                symbol: "puzzlepiece.extension.fill", topColor: .purple, bottomColor: .indigo,
                title: "插件生态与原生 MCP Server",
                subtitle: "脚本插件按需触发执行并自动回收子进程，支持搭配 lumakey-mcp 由 AI 自动生成与校验扩展。"
            ) {
                Button("复制 MCP JSON 配置") {
                    let mcpPath = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/lumakey-mcp").path
                    let snippet = "{\n  \"mcpServers\": {\n    \"lumakey\": {\n      \"command\": \"\(mcpPath)\",\n      \"args\": []\n    }\n  }\n}"
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(snippet, forType: .string)
                    viewModel.serviceMessage = "已复制 lumakey-mcp 配置 JSON"
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
            PluginCenterView(viewModel: viewModel)
        }
    }

    private var shortcutsSection: some View {
        let rows: [(key: String, title: String, desc: String, symbol: String, top: Color, bottom: Color)] = [
            ("⌥ Space", "全局统一快捷中枢", "毫秒呼出应用、文件、剪贴板、换算与指令", "sparkles", .cyan, .blue),
            ("⌥ F", "Everything 秒搜面板", "直达全盘 + 外置磁盘文件搜索与右侧预览", "magnifyingglass", .teal, .indigo),
            ("⌥ C", "智能剪贴板历史库", "检索文本、#HEX 色值、图片与文件路径", "doc.on.clipboard.fill", .orange, .pink),
            ("⌥ A", "QQ 式原生截图标注", "窗口吸附、放大镜取色、涂鸦马赛克与钉屏", "camera.viewfinder", .mint, .teal),
            ("⌥ O", "截图离线 Vision OCR", "CPU 绑定极速识别中英文本与二维码", "text.viewfinder", .indigo, .purple),
            ("⌥ M", "系统脉搏监控悬浮窗", "开启或隐藏 CPU / 频率 / 内存 / 功耗 / 网速", "waveform.path.ecg", .mint, .cyan),
            ("⌥ N", "本机网络流量与去向", "实时查看各进程网速、远端 IP 域名与连接状态", "network", .cyan, .teal),
            ("⌥ E", "双栏文件与 NTFS 台", "列表/网格/紧凑多视图与居中多媒体预览", "externaldrive.fill", .blue, .indigo),
            ("⌘Y / ⌘R / ⌘,", "面板内快捷控制键", "切换侧边预览 / 访达定位 / 打开流光设置", "keyboard", .purple, .pink)
        ]
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeroHeader(
                    symbol: "command.square.fill", topColor: .mint, bottomColor: .teal,
                    title: "全局热键与键盘工作流",
                    subtitle: "全系统任意应用下随时唤起；支持全键盘上下移动、Tab 切换分类、Enter 执行与 Esc 逐级收起。"
                )
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(rows, id: \.key) { row in
                        HStack(spacing: 10) {
                            SquircleBadge(symbol: row.symbol, topColor: row.top, bottomColor: row.bottom, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title).font(.callout.weight(.semibold))
                                Text(row.desc).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(row.key)
                                .font(.caption2.monospaced().weight(.bold))
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(LiquidColors.pillSurface, in: Capsule())
                                .overlay { Capsule().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                        }
                        .padding(11)
                        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 10) {
                    SquircleBadge(symbol: "sparkles", topColor: .cyan, bottomColor: .indigo, size: 60)
                    Text("流光 Lumakey 0.6.5").font(.title2.weight(.bold))
                    Text("Apple Silicon (arm64) 原生 Swift 6 · 零第三方依赖 · Build 15")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text("轻量级菜单栏高效快捷中枢：以液态玻璃美学统合全局检索、QQ 式截图标注、离线 Vision OCR、内置 Mos 平滑滚轮与零 WebKit 文档阅读器。")
                        .font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 520)
                }
                .padding(20).frame(maxWidth: .infinity)
                .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)

                HStack(spacing: 10) {
                    aboutPillar("cpu", .cyan, "Native Services First", "完全基于 SwiftUI、AppKit、Vision 与 CoreGraphics 原生构建，无任何外部依赖或 Electron 壳。")
                    aboutPillar("leaf.arrow.circlepath", .green, "最优内存自洁架构", "浮窗隐藏 30s 回收视图树，索引按需驻留 · 空闲 90s 卸载（保留 LMKYIDX2 快照），独立窗口关闭即销毁。")
                    aboutPillar("shield.lefthalf.filled", .orange, "无感静默启动策略", "全部悬浮监控与顶部实时状态新装默认关闭，不安装任何 launchd 后台常驻守护进程。")
                }
            }
        }
    }

    private func aboutPillar(_ symbol: String, _ color: Color, _ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(color)
            Text(title).font(.callout.weight(.semibold))
            Text(desc).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }
}
