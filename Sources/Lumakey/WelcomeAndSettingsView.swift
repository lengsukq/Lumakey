import AppKit
import LumakeyCore
import SwiftUI

struct WelcomeGuideView: View {
    @ObservedObject var viewModel: AppViewModel

    private let highlights: [(symbol: String, top: Color, bottom: Color, title: String, desc: String)] = [
        ("sparkles", .cyan, .blue, "全局快捷中枢 (⌥Space)", "拼音/首字母毫秒启动应用，内联算式、进制与单位换算"),
        ("magnifyingglass", .teal, .indigo, "全盘 Everything 秒搜 (⌥F)", "开箱即搜本机与全部外置盘 + ext:/video:/pic:/path:/! 语法"),
        ("network", .cyan, .teal, "本机网络流量监控 (⌥N)", "零特权实时拆解进程网速、远端 IP 域名去向与连接状态"),
        ("internaldrive.fill", .orange, .indigo, "应用缓存与置顶播片", "分类管理剪贴板/截图/抠图/转封装缓存；图片视频支持置顶与同目录连播"),
        ("camera.viewfinder", .mint, .teal, "QQ 式截图标注 (⌥A / ⌥O)", "窗口吸附、放大镜取色、涂鸦马赛克、悬浮钉屏与 Vision OCR"),
        ("sidebar.squares.left", .blue, .indigo, "多视图文件台 (⌥E)", "列表/网格/紧凑三视图、6 维排序、7 类筛选与居中多媒体预览")
    ]

    var body: some View {
        SecondaryWindowScaffold(title: "欢迎使用 流光 Lumakey", subtitle: "v0.6.5 · arm64", symbol: "sparkles", pinWindowKey: "welcome") {
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    SquircleBadge(symbol: "sparkles", topColor: .cyan, bottomColor: .indigo, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("流光 Lumakey").font(.title2.weight(.bold))
                        Text("为 Apple Silicon 原生打造的超通透毛玻璃效率中枢 · 菜单栏常驻，呼之即来")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("立即呼出快捷台 (⌥Space)") { viewModel.showOverlay(filter: .all) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                }
                .padding(16)
                .liquidGlassCard(cornerRadius: LiquidRadii.bento)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(highlights, id: \.title) { item in
                        HStack(alignment: .center, spacing: 14) {
                            SquircleBadge(symbol: item.symbol, topColor: item.top, bottomColor: item.bottom, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.callout.weight(.semibold))
                                Text(item.desc).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 4)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
                    }
                }

                HStack(spacing: 8) {
                    Button("网络流量 (⌥N)") { viewModel.openRoute(.networkMonitor) }.buttonStyle(GlassPillButtonStyle())
                    Button("系统脉搏 (⌥M)") { viewModel.openRoute(.settings(.monitor)) }.buttonStyle(GlassPillButtonStyle())
                    Button("应用缓存管理") { viewModel.openRoute(.settings(.cache)) }.buttonStyle(GlassPillButtonStyle())
                    Button("文件工作台 (⌥E)") { viewModel.openRoute(.workspace) }.buttonStyle(GlassPillButtonStyle())
                    Spacer()
                    Text("悬浮窗与顶部状态读数默认关闭")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .liquidGlassCard(cornerRadius: LiquidRadii.card)
            }
        }
        .frame(minWidth: 820, minHeight: 550)
    }
}

struct SettingsCenterView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        SecondaryWindowScaffold(title: "流光设置与扩展中心", subtitle: viewModel.activeSettingsSection.title, symbol: "slider.horizontal.3", pinWindowKey: "settings") {
            HStack(spacing: 12) {
                sidebar
                detailPane
            }
        }
        .frame(minWidth: 960, minHeight: 620)
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                Text("流光设置").font(.headline).padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 2)
                ForEach(SettingsSection.allCases) { section in
                    let active = viewModel.activeSettingsSection == section
                    Button { viewModel.activeSettingsSection = section } label: {
                        HStack(alignment: .center, spacing: 10) {
                            SquircleBadge(symbol: section.symbolName, topColor: section.badgeColors.top, bottomColor: section.badgeColors.bottom, size: 28)
                            Text(section.title).font(.callout.weight(active ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(active ? LiquidColors.highlightGlow : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(width: 214)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }

    @ViewBuilder
    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewModel.activeSettingsSection {
            case .general: generalSection
            case .monitor: TelemetrySettingsView()
            case .network:
                NetworkMonitorCoreView(embeddedInSettings: true) {
                    viewModel.openRoute(.networkMonitor)
                }
            case .cache:
                ScrollView { AppCacheSettingsView(viewModel: viewModel) }
            case .mos: MosPluginSettingsView(viewModel: viewModel)
            default: SettingsDetailSectionsView(viewModel: viewModel, section: viewModel.activeSettingsSection)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }

    private var generalSection: some View {
        let memMB = String(format: "%.1f MB", MemoryStats.currentPhysicalFootprintMB())
        let pulseState = SystemPulseWindowController.shared.state
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeroHeader(
                    symbol: "slider.horizontal.3", topColor: .cyan, bottomColor: .blue,
                    title: "通用驻留与内存自洁架构",
                    subtitle: "刚安装保持零无用常驻界面：悬浮窗、菜单栏实时读数与程序坞图标全部默认关闭，按需开启。"
                ) {
                    Button("立即释放空闲内存") { viewModel.reclaimAllIdleMemoryNow() }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                }

                SettingsToggleCardRow(
                    symbol: "macwindow", topColor: .blue, bottomColor: .indigo,
                    title: "关闭全部窗口后仍在程序坞 (Dock) 常驻图标", subtitle: "打开文件工作台、影院播放、阅读或设置窗口时会自动显示 Dock 图标；仅全部关闭后按此开关收起",
                    isOn: Binding(get: { viewModel.showDockIcon }, set: { viewModel.setDockIconVisible($0) })
                )
                SettingsToggleCardRow(
                    symbol: "waveform.path.ecg", topColor: .mint, bottomColor: .cyan,
                    title: "系统脉搏桌面监控悬浮窗 (快捷键 ⌥M)", subtitle: "默认关闭 · 支持顶部精简胶囊、点击展开趋势与贴边自动隐藏",
                    isOn: Binding(get: { pulseState.config.floatingEnabled }, set: { SystemPulseWindowController.shared.setFloatingEnabled($0) })
                )
                SettingsToggleCardRow(
                    symbol: "menubar.rectangle", topColor: .teal, bottomColor: .blue,
                    title: "在顶部菜单栏显示实时系统状态", subtitle: "默认关闭 · 可进入“系统监控”自定义 CPU / 频率 / 内存 / 功耗 / 网速",
                    isOn: Binding(get: { pulseState.config.showInMenuBar }, set: { SystemPulseWindowController.shared.setMenuBarEnabled($0) })
                )
                SettingsToggleCardRow(
                    symbol: "computermouse.fill", topColor: .cyan, bottomColor: .indigo,
                    title: "Mos 物理鼠标平滑滚动与方向反转", subtitle: "默认关闭 · 仅作用于外接鼠标滚轮，完全保留触控板自然滚动",
                    isOn: Binding(
                        get: { viewModel.mosConfig.enabled },
                        set: { enabled in var next = viewModel.mosConfig; next.enabled = enabled; viewModel.applyMosConfig(next) }
                    )
                )

                HStack(spacing: 10) {
                    metricBox("当前物理内存占用", value: memMB, hint: "隐藏 30s 自动销毁主面板视图")
                    metricBox("Everything 索引", value: "\(viewModel.everythingNodeCount) 节点", hint: "按需加载 · 空闲 90s 卸载（保留快照）")
                    metricBox("受控子进程", value: "\(viewModel.activeProcessCount) 个", hint: "8s 超时强杀与退出清理")
                }

                signingStatusCard

                HStack(spacing: 8) {
                    Button("自定义监控指标与风格…") { viewModel.activeSettingsSection = .monitor }.buttonStyle(GlassPillButtonStyle())
                    Button("Mos 详细参数…") { viewModel.activeSettingsSection = .mos }.buttonStyle(GlassPillButtonStyle())
                    Button("关闭所有屏幕钉图") { PinWindowController.shared.closeAll() }.buttonStyle(GlassPillButtonStyle())
                    Spacer()
                    Text("ntfs-3g: \(viewModel.toolingStatus.ntfs3gPath != nil ? "就绪" : "未安装") · ffmpeg: \(viewModel.toolingStatus.ffmpegPath != nil ? "就绪" : "未安装")")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var signingStatusCard: some View {
        let sign = CodeSigningInspector.inspect()
        return HStack(spacing: 12) {
            SquircleBadge(
                symbol: sign.isStableForTCC ? "checkmark.seal.fill" : "exclamationmark.shield.fill",
                topColor: sign.isStableForTCC ? .green : .orange,
                bottomColor: sign.isStableForTCC ? .teal : .red,
                size: 32
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(sign.badgeTitle).font(.callout.weight(.semibold))
                Text(sign.explanation).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !sign.isStableForTCC {
                Button("复制固定签名命令") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("cd /Volumes/lightlsle/Code/Lumakey && bash scripts/setup-local-signing.sh", forType: .string)
                    viewModel.serviceMessage = "已复制签名配置命令，请在终端粘贴运行一次即可升级免重授权"
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }

    private func metricBox(_ label: String, value: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.bold).monospacedDigit())
            Text(hint).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }
}
