import CoreGraphics
import Foundation

public enum PulseDockEdge: String, Codable, CaseIterable, Sendable {
    case none
    case top
    case left
    case right

    public var isVerticalColumn: Bool { self == .left || self == .right }
    public var isHorizontalStrip: Bool { self == .top || self == .none }

    public static func detectSnapEdge(frame: CGRect, visibleFrame: CGRect) -> PulseDockEdge {
        var candidates: [(PulseDockEdge, CGFloat)] = []
        let topDist = visibleFrame.maxY - frame.maxY
        let leftDist = frame.minX - visibleFrame.minX
        let rightDist = visibleFrame.maxX - frame.maxX
        if topDist <= 28 { candidates.append((.top, max(0, topDist))) }
        if leftDist <= 34 { candidates.append((.left, max(0, leftDist))) }
        if rightDist <= 34 { candidates.append((.right, max(0, rightDist))) }
        return candidates.min(by: { $0.1 < $1.1 })?.0 ?? .none
    }

    public static func nearestEdge(for frame: CGRect, visibleFrame: CGRect) -> PulseDockEdge {
        let topDist = abs(visibleFrame.maxY - frame.maxY)
        let leftDist = abs(frame.minX - visibleFrame.minX)
        let rightDist = abs(visibleFrame.maxX - frame.maxX)
        let all: [(PulseDockEdge, CGFloat)] = [(.top, topDist), (.left, leftDist), (.right, rightDist)]
        return all.min(by: { $0.1 < $1.1 })?.0 ?? .right
    }

    public func panelOrigin(size: CGSize, currentFrame cur: CGRect, visibleFrame vis: CGRect, savedX: Double?, savedY: Double?) -> CGPoint {
        let curTop = cur.height > 10 ? cur.maxY : (vis.midY + size.height / 2)
        let clampedY = min(max(vis.minY + 18, curTop - size.height), vis.maxY - size.height - 10)
        switch self {
        case .left:
            return CGPoint(x: vis.minX + 3, y: clampedY)
        case .right:
            return CGPoint(x: vis.maxX - size.width - 3, y: clampedY)
        case .top:
            let midX = cur.width > 10 ? cur.midX : CGFloat(savedX ?? Double(vis.midX))
            let x = min(max(vis.minX + 16, midX - size.width / 2), vis.maxX - size.width - 16)
            return CGPoint(x: x, y: vis.maxY - size.height - 3)
        case .none:
            if cur.width > 10 && cur.origin != .zero {
                let rawX = cur.midX > vis.midX ? (cur.maxX - size.width) : cur.minX
                return CGPoint(x: min(max(vis.minX + 12, rawX), vis.maxX - size.width - 12), y: clampedY)
            } else if let sx = savedX, let sy = savedY, vis.contains(CGPoint(x: sx, y: sy)) {
                let x = min(max(vis.minX + 12, CGFloat(sx)), vis.maxX - size.width - 12)
                let y = min(max(vis.minY + 18, CGFloat(sy) - size.height), vis.maxY - size.height - 10)
                return CGPoint(x: x, y: y)
            }
            return CGPoint(x: vis.maxX - size.width - 18, y: vis.maxY - size.height - 10)
        }
    }
}

public enum TelemetryDisplayMode: String, Codable, CaseIterable, Sendable {
    case compactHoverExpand
    case alwaysExpanded
    case edgeAutoHide

    public var title: String {
        switch self {
        case .compactHoverExpand: "顶部精简 · 悬停展开"
        case .alwaysExpanded: "完整常驻"
        case .edgeAutoHide: "贴边自动隐藏"
        }
    }
}

public struct SystemMonitorConfig: Codable, Equatable, Sendable {
    public var floatingEnabled: Bool = false
    public var showInMenuBar: Bool = false
    public var displayMode: TelemetryDisplayMode = .compactHoverExpand
    public var dockedEdgeRaw: String = "none"
    public var savedOriginX: Double? = nil

    public var dockedEdge: PulseDockEdge {
        get { PulseDockEdge(rawValue: dockedEdgeRaw) ?? .none }
        set { dockedEdgeRaw = newValue.rawValue }
    }
    public var savedOriginY: Double? = nil
    public var menuShowCPU: Bool = true
    public var menuShowFreq: Bool = false
    public var menuShowMemory: Bool = true
    public var menuShowPower: Bool = true
    public var menuShowNet: Bool = true

    public init() {}

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Lumakey/telemetry-v2.json")
    }

    public static func load(from url: URL = defaultURL) -> SystemMonitorConfig {
        if url == defaultURL {
            let legacy = url.deletingLastPathComponent().appendingPathComponent("telemetry-config.json")
            try? FileManager.default.removeItem(at: legacy)
        }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(SystemMonitorConfig.self, from: data) else {
            return SystemMonitorConfig()
        }
        return decoded
    }

    public func save(to url: URL = defaultURL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public func formatMenuBarText(from snap: SystemTelemetrySnapshot) -> String {
        var parts: [String] = []
        if menuShowCPU { parts.append(String(format: "%.0f%%", snap.cpuTotalPercent)) }
        if menuShowFreq { parts.append(String(format: "%.2fG", snap.estimatedFrequencyGHz)) }
        if menuShowMemory { parts.append(String(format: "M%.0f%%", snap.memoryPercent)) }
        if menuShowPower { parts.append(String(format: "%.1fW", snap.systemWatts)) }
        if menuShowNet { parts.append("↓\(SystemTelemetrySnapshot.formatShortRate(snap.netDownBytesPerSec))") }
        return parts.isEmpty ? snap.menuBarCompactText : parts.joined(separator: " ")
    }
}

public struct SystemTelemetrySnapshot: Sendable, Equatable {
    public var cpuTotalPercent: Double = 0
    public var perfCorePercent: Double = 0
    public var effCorePercent: Double = 0
    public var estimatedFrequencyGHz: Double = 0
    public var maxFrequencyGHz: Double = 4.2
    public var chipBrand: String = "Apple Silicon"
    public var coreTopologyText: String = "多核"
    public var thermalStateLabel: String = "正常"
    public var gpuPercent: Double = 0
    public var memoryUsedBytes: UInt64 = 0
    public var memoryTotalBytes: UInt64 = 0
    public var memoryPercent: Double = 0
    public var memoryCompressedBytes: UInt64 = 0
    public var swapUsedMB: Double = 0
    public var systemWatts: Double = 0
    public var batteryPercent: Int? = nil
    public var isCharging: Bool = false
    public var netDownBytesPerSec: Double = 0
    public var netUpBytesPerSec: Double = 0
    public var diskFreeGB: Double = 0
    public var diskTotalGB: Double = 0
    public var cpuHistory: [Double] = []
    public var memHistory: [Double] = []
    public var powerHistory: [Double] = []
    public var netHistory: [Double] = []

    public static let placeholder = SystemTelemetrySnapshot()

    public var formattedNetDown: String { Self.formatRate(netDownBytesPerSec) }
    public var formattedNetUp: String { Self.formatRate(netUpBytesPerSec) }
    public var formattedFrequency: String { String(format: "%.2f GHz", estimatedFrequencyGHz) }
    public var formattedPower: String { String(format: "%.1f W", systemWatts) }
    public var formattedMemory: String {
        let gb = 1_073_741_824.0
        return String(format: "%.1f / %.0f GB", Double(memoryUsedBytes) / gb, max(1.0, Double(memoryTotalBytes) / gb))
    }

    public var menuBarCompactText: String {
        String(format: "%.0f%% %.1fW ↓%@", cpuTotalPercent, systemWatts, Self.formatShortRate(netDownBytesPerSec))
    }

    public static func formatRate(_ bytesPerSec: Double) -> String {
        let rate = max(0, bytesPerSec)
        if rate < 1024 { return "\(Int(rate)) B/s" }
        if rate < 1_048_576 { return String(format: "%.0f KB/s", rate / 1024.0) }
        if rate < 1_073_741_824 { return String(format: "%.1f MB/s", rate / 1_048_576.0) }
        return String(format: "%.2f GB/s", rate / 1_073_741_824.0)
    }

    public static func formatShortRate(_ bytesPerSec: Double) -> String {
        let rate = max(0, bytesPerSec)
        if rate < 1024 { return "0K" }
        if rate < 1_048_576 { return String(format: "%.0fK", rate / 1024.0) }
        if rate < 1_073_741_824 { return String(format: "%.1fM", rate / 1_048_576.0) }
        return String(format: "%.1fG", rate / 1_073_741_824.0)
    }
}