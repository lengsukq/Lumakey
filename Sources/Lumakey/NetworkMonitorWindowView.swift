import AppKit
import LumakeyCore
import SwiftUI

struct NetworkMonitorWindowView: View {
    var body: some View {
        SecondaryWindowScaffold(
            title: "本机网络流量与去向监控",
            subtitle: "按应用拆解实时上下行速率 · 远端 IP 与域名去向 · 连接状态",
            symbol: "network",
            pinWindowKey: "networkMonitor"
        ) {
            NetworkMonitorCoreView(embeddedInSettings: false)
        }
        .frame(minWidth: 920, minHeight: 580)
    }
}

struct NetworkMonitorCoreView: View {
    let embeddedInSettings: Bool
    var onOpenStandaloneWindow: (() -> Void)? = nil
    @StateObject private var controller = NetworkMonitorController()

    var body: some View {
        VStack(spacing: 12) {
            if !embeddedInSettings { headerHeroBar }
            controlsAndKPIStrip
            splitBody
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }

    private var headerHeroBar: some View {
        SettingsSectionHeroHeader(
            symbol: "network",
            topColor: .cyan,
            bottomColor: .blue,
            title: "实时网络流量与连接去向",
            subtitle: "基于系统 nettop 零特权采样，仅在窗口打开时运行，关闭即零驻留释放。"
        ) {
            HStack(spacing: 8) {
                Button { controller.togglePaused() } label: {
                    Label(controller.isPaused ? "继续采样" : "暂停", systemImage: controller.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(GlassPillButtonStyle(prominent: controller.isPaused))

                Button { controller.refreshNow() } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GlassPillButtonStyle())
            }
        }
    }

    private var controlsAndKPIStrip: some View {
        let s = controller.snapshot
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                kpiPill(title: "总下行 ↓", value: NetworkTrafficParser.formatRate(s.totalDownBytesPerSec), accent: .cyan)
                kpiPill(title: "总上行 ↑", value: NetworkTrafficParser.formatRate(s.totalUpBytesPerSec), accent: .orange)
                kpiPill(title: "活跃进程", value: "\(s.processes.count)", accent: .indigo)
                kpiPill(title: "外网目标 IP", value: "\(s.externalHostCount)", accent: .mint)
                if let openStandalone = onOpenStandaloneWindow {
                    Button(action: openStandalone) {
                        Label("独立窗口 (⌥N)", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                }
            }
            HStack(spacing: 5) {
                GlassInputField(
                    symbol: "magnifyingglass",
                    placeholder: embeddedInSettings ? "搜索应用 / PID / IP / 域名…" : "过滤应用名 / PID / 远端 IP / 域名 / 协议…",
                    text: $controller.searchText
                )
                .frame(minWidth: 136, maxWidth: .infinity)
                .layoutPriority(-1)

                ForEach(NetworkFilterMode.allCases) { mode in
                    Button(mode.title) { controller.filterMode = mode }
                        .buttonStyle(GlassPillButtonStyle(prominent: controller.filterMode == mode))
                }
                Menu {
                    ForEach(NetworkSortField.allCases) { field in
                        Button { controller.sortField = field } label: {
                            if controller.sortField == field { Label(field.title, systemImage: "checkmark") } else { Text(field.title) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 10, weight: .semibold))
                        Text(controller.sortField.title).font(.caption.weight(.semibold))
                        Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).foregroundStyle(LiquidColors.textSecondary)
                    }
                    .foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10).padding(.vertical, 5.5)
                    .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
                    .overlay { Capsule(style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.8) }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: LiquidRadii.card)
    }

    private var splitBody: some View {
        let processes = controller.filteredProcesses
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("应用流量排行 (\(processes.count))").font(.caption.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                    Spacer()
                    if controller.isSampling { ProgressView().controlSize(.mini) }
                }
                .padding(.horizontal, 4)

                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(processes) { proc in processRow(proc) }
                    }
                    .padding(8)
                }
                .liquidGlassCard(cornerRadius: LiquidRadii.bento)
            }
            .frame(width: embeddedInSettings ? 276 : 344)
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("连接去向明细（IP · 域名 · 协议 · 接口）").font(.caption.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                    .padding(.horizontal, 4)

                if let selected = controller.selectedProcess {
                    processDestinationDetail(selected)
                } else {
                    ContentUnavailableView("暂无网络连接数据", systemImage: "network.slash")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func processRow(_ proc: ProcessTrafficSummary) -> some View {
        let selected = controller.selectedProcess?.pid == proc.pid
        let shape = RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous)
        return Button {
            controller.selectProcess(proc.pid)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                processIcon(proc, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(proc.displayName).font(.callout.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
                        Text("#\(proc.pid)").font(.system(size: 10, design: .monospaced)).foregroundStyle(LiquidColors.textSecondary)
                    }
                    Text("\(proc.connections.count) 连接 · \(proc.externalHostPreview)")
                        .font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("↓ \(NetworkTrafficParser.formatRate(proc.downBytesPerSec))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(proc.downBytesPerSec > 0 ? .cyan : LiquidColors.textSecondary)
                    Text("↑ \(NetworkTrafficParser.formatRate(proc.upBytesPerSec))")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(proc.upBytesPerSec > 0 ? .orange : LiquidColors.textSecondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(selected ? LiquidColors.highlightGlow : LiquidColors.pillSurface.opacity(0.32), in: shape)
            .overlay { shape.strokeBorder(selected ? Color.accentColor.opacity(0.5) : LiquidColors.pillBorder.opacity(0.45), lineWidth: 0.85) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    private func processDestinationDetail(_ proc: ProcessTrafficSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                processIcon(proc, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(proc.displayName)  (PID \(proc.pid))").font(.headline).foregroundStyle(LiquidColors.textPrimary)
                    Text(proc.executablePath ?? proc.processName).font(.caption2.monospaced()).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("累计收 \(NetworkTrafficParser.formatBytes(proc.bytesIn))").font(.caption2.monospacedDigit()).foregroundStyle(.cyan)
                    Text("累计发 \(NetworkTrafficParser.formatBytes(proc.bytesOut))").font(.caption2.monospacedDigit()).foregroundStyle(.orange)
                }
                if let revealPath = proc.bundleAppPath ?? proc.executablePath {
                    Button("访达") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: revealPath)]) }
                        .buttonStyle(GlassPillButtonStyle())
                }
            }
            .padding(12)
            .liquidGlassCard(cornerRadius: LiquidRadii.card)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(proc.connections) { conn in connectionRow(conn) }
                }
                .padding(8)
            }
            .liquidGlassCard(cornerRadius: LiquidRadii.bento)
        }
    }

    private func connectionRow(_ conn: NetworkConnectionItem) -> some View {
        let hostDomain = controller.resolvedHosts[conn.remoteHost]
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(conn.serviceTag)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(conn.isExternal ? .white : LiquidColors.textPrimary)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(conn.isExternal ? Color.cyan.opacity(0.85) : LiquidColors.pillSurface, in: Capsule())
                    Text(conn.remoteEndpoint)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(LiquidColors.textPrimary).lineLimit(1).truncationMode(.middle)
                    if let hostDomain {
                        Text("· \(hostDomain)").font(.caption2).foregroundStyle(.cyan).lineLimit(1).truncationMode(.middle)
                    }
                }
                Text("\(conn.proto.uppercased()) · 接口 \(conn.interfaceName) · 状态 \(conn.state) · 本地 \(conn.localEndpoint)")
                    .font(.caption2.monospaced()).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text("收 \(NetworkTrafficParser.formatBytes(conn.bytesIn))").font(.caption2.monospacedDigit()).foregroundStyle(LiquidColors.textPrimary)
                Text("发 \(NetworkTrafficParser.formatBytes(conn.bytesOut))").font(.caption2.monospacedDigit()).foregroundStyle(LiquidColors.textSecondary)
            }
            if conn.remoteHost != "*" && !conn.remoteHost.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hostDomain ?? conn.remoteHost, forType: .string)
                } label: { Image(systemName: "doc.on.doc").font(.caption2) }
                .buttonStyle(GlassPillButtonStyle())
                .help("复制远端目标地址")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .liquidGlassCard(cornerRadius: LiquidRadii.row)
    }

    @ViewBuilder
    private func processIcon(_ proc: ProcessTrafficSummary, size: CGFloat) -> some View {
        if let appPath = proc.bundleAppPath {
            Image(nsImage: IconCache.shared.appIcon(for: URL(fileURLWithPath: appPath)))
                .resizable().frame(width: size, height: size)
        } else {
            SquircleBadge(symbol: "app.connected.to.app.below.fill", topColor: .cyan, bottomColor: .indigo, size: size)
        }
    }

    private func kpiPill(title: String, value: String, accent: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(accent).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(LiquidColors.textSecondary)
                Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(LiquidColors.textPrimary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.row)
    }
}
