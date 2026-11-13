import Foundation

public enum NetworkFilterMode: String, CaseIterable, Sendable, Identifiable {
    case all, activeRate, externalOnly, listening
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: "全部进程"
        case .activeRate: "实时活跃"
        case .externalOnly: "外网去向"
        case .listening: "端口监听"
        }
    }
}

public enum NetworkSortField: String, CaseIterable, Sendable, Identifiable {
    case liveRate, totalBytes, connections, name
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .liveRate: "实时网速"
        case .totalBytes: "累计流量"
        case .connections: "连接数量"
        case .name: "进程名称"
        }
    }
}

public struct NetworkConnectionItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let proto: String
    public let localEndpoint: String
    public let remoteEndpoint: String
    public let remoteHost: String
    public let remotePort: Int?
    public let interfaceName: String
    public let state: String
    public let bytesIn: Int64
    public let bytesOut: Int64
    public let serviceTag: String
    public let isExternal: Bool
    public let isListening: Bool
}

public struct ProcessTrafficSummary: Identifiable, Hashable, Sendable {
    public let id: Int32
    public let pid: Int32
    public let processName: String
    public let displayName: String
    public let executablePath: String?
    public let bundleAppPath: String?
    public let bytesIn: Int64
    public let bytesOut: Int64
    public let downBytesPerSec: Double
    public let upBytesPerSec: Double
    public let connections: [NetworkConnectionItem]

    public var totalRate: Double { downBytesPerSec + upBytesPerSec }
    public var totalBytes: Int64 { bytesIn + bytesOut }
    public var hasExternalConnection: Bool { connections.contains(where: \.isExternal) }
    public var hasListeningSocket: Bool { connections.contains(where: \.isListening) }
    public var externalHostPreview: String {
        var seen: [String] = []
        for conn in connections where conn.isExternal && !conn.remoteHost.isEmpty {
            if !seen.contains(conn.remoteHost) { seen.append(conn.remoteHost) }
            if seen.count >= 2 { break }
        }
        return seen.isEmpty ? (hasListeningSocket ? "本机监听端口" : "本机 / 待机") : seen.joined(separator: " · ")
    }
}

public struct NetworkTrafficSnapshot: Sendable {
    public let sampledAt: Date
    public let processes: [ProcessTrafficSummary]
    public let totalDownBytesPerSec: Double
    public let totalUpBytesPerSec: Double
    public let activeConnectionCount: Int
    public let externalHostCount: Int

    public static let empty = NetworkTrafficSnapshot(
        sampledAt: .distantPast, processes: [], totalDownBytesPerSec: 0, totalUpBytesPerSec: 0, activeConnectionCount: 0, externalHostCount: 0
    )
}

public enum NetworkTrafficParser {
    public static func parseNettopCSV(
        _ csv: String,
        previous: [Int32: (bytesIn: Int64, bytesOut: Int64)],
        elapsed: TimeInterval,
        sampledAt: Date = Date(),
        resolver: (Int32, String) -> (displayName: String, executablePath: String?, bundleAppPath: String?)
    ) -> (snapshot: NetworkTrafficSnapshot, counters: [Int32: (bytesIn: Int64, bytesOut: Int64)]) {
        var processes: [ProcessTrafficSummary] = []
        var counters: [Int32: (bytesIn: Int64, bytesOut: Int64)] = [:]
        var activeCount = 0
        var externalHosts: Set<String> = []
        var curPid: Int32?
        var curProcName = ""
        var curIn: Int64 = 0
        var curOut: Int64 = 0
        var curConns: [NetworkConnectionItem] = []

        func flushCurrent() {
            guard let pid = curPid else { return }
            counters[pid] = (curIn, curOut)
            let prev = previous[pid]
            let canDelta = prev != nil && elapsed > 0.05
            let downRate = (canDelta && curIn >= (prev?.bytesIn ?? 0)) ? Double(curIn - (prev?.bytesIn ?? 0)) / elapsed : 0
            let upRate = (canDelta && curOut >= (prev?.bytesOut ?? 0)) ? Double(curOut - (prev?.bytesOut ?? 0)) / elapsed : 0
            let meta = resolver(pid, curProcName)
            let sortedConns = curConns.sorted { ($0.bytesIn + $0.bytesOut) > ($1.bytesIn + $1.bytesOut) }
            processes.append(ProcessTrafficSummary(
                id: pid, pid: pid, processName: curProcName, displayName: meta.displayName,
                executablePath: meta.executablePath, bundleAppPath: meta.bundleAppPath,
                bytesIn: curIn, bytesOut: curOut, downBytesPerSec: downRate, upBytesPerSec: upRate, connections: sortedConns
            ))
            curPid = nil; curConns = []
        }

        for rawLine in csv.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(",interface,") { continue }
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 5 else { continue }
            let col0 = cols[0], iface = cols[1], state = cols[2]
            let bIn = Int64(cols[3]) ?? 0, bOut = Int64(cols[4]) ?? 0

            if iface.isEmpty && state.isEmpty, let dot = col0.lastIndex(of: "."),
               let pid = Int32(col0[col0.index(after: dot)...]), !col0.contains("<->") {
                flushCurrent()
                curPid = pid; curProcName = String(col0[..<dot]); curIn = bIn; curOut = bOut
            } else if curPid != nil, col0.contains("<->") {
                let conn = parseSocketRow(col0: col0, iface: iface, state: state, bytesIn: bIn, bytesOut: bOut, index: curConns.count)
                curConns.append(conn)
                activeCount += 1
                if conn.isExternal && !conn.remoteHost.isEmpty { externalHosts.insert(conn.remoteHost) }
            }
        }
        flushCurrent()

        let totalDown = processes.reduce(0.0) { $0 + $1.downBytesPerSec }
        let totalUp = processes.reduce(0.0) { $0 + $1.upBytesPerSec }
        let snapshot = NetworkTrafficSnapshot(
            sampledAt: sampledAt, processes: processes, totalDownBytesPerSec: totalDown,
            totalUpBytesPerSec: totalUp, activeConnectionCount: activeCount, externalHostCount: externalHosts.count
        )
        return (snapshot, counters)
    }

    private static func parseSocketRow(col0: String, iface: String, state: String, bytesIn: Int64, bytesOut: Int64, index: Int) -> NetworkConnectionItem {
        let spaceParts = col0.split(separator: " ", maxSplits: 1).map(String.init)
        let proto = spaceParts.first ?? "sock"
        let endpoints = (spaceParts.count > 1 ? spaceParts[1] : col0).components(separatedBy: "<->")
        let local = endpoints.first ?? "*"
        let remote = endpoints.count > 1 ? endpoints[1] : "*"
        let (host, port) = splitHostAndPort(remote)
        let classified = classifyServiceTag(proto: proto, remoteHost: host, remotePort: port, interfaceName: iface, state: state)
        return NetworkConnectionItem(
            id: "\(index)-\(proto)-\(local)-\(remote)-\(iface)", proto: proto, localEndpoint: local, remoteEndpoint: remote,
            remoteHost: host, remotePort: port, interfaceName: iface.isEmpty ? "-" : iface, state: state.isEmpty ? "无连接/UDP" : state,
            bytesIn: bytesIn, bytesOut: bytesOut, serviceTag: classified.tag, isExternal: classified.isExternal, isListening: classified.isListening
        )
    }

    public static func splitHostAndPort(_ endpoint: String) -> (host: String, port: Int?) {
        if endpoint == "*:*" || endpoint == "*.*" || endpoint.isEmpty { return ("*", nil) }
        if endpoint.hasPrefix("["), let close = endpoint.firstIndex(of: "]") {
            let host = String(endpoint[endpoint.index(after: endpoint.startIndex)..<close])
            let after = endpoint[endpoint.index(after: close)...]
            let port = after.hasPrefix(":") ? Int(after.dropFirst()) : nil
            return (host, port)
        }
        if let colon = endpoint.lastIndex(of: ":"), endpoint.firstIndex(of: ":") == colon || endpoint.contains(".") {
            let host = String(endpoint[..<colon])
            let port = Int(endpoint[endpoint.index(after: colon)...])
            return (host, port)
        }
        if let dot = endpoint.lastIndex(of: "."), endpoint.contains("::") || endpoint.filter({ $0 == "." }).count == 1 {
            let host = String(endpoint[..<dot])
            let port = Int(endpoint[endpoint.index(after: dot)...])
            return (host, port)
        }
        return (endpoint, nil)
    }

    public static func classifyServiceTag(proto: String, remoteHost: String, remotePort: Int?, interfaceName: String, state: String) -> (tag: String, isExternal: Bool, isListening: Bool) {
        if state.localizedCaseInsensitiveContains("Listen") || remoteHost == "*" || remoteHost.isEmpty {
            return ("端口监听", false, true)
        }
        let isLocal = isPrivateOrLoopbackHost(remoteHost)
        let isExternal = !isLocal
        let isTun = interfaceName.hasPrefix("utun")
        if isLocal && !isTun {
            if remotePort == 5353 { return ("mDNS 发现", false, false) }
            if remotePort == 445 { return ("局域网 SMB", false, false) }
            return ("内网/回环", false, false)
        }
        let prefix = isTun ? "TUN · " : ""
        let service: String
        switch remotePort {
        case 443: service = remoteHost.hasPrefix("17.") ? "Apple HTTPS" : "HTTPS"
        case 80: service = "HTTP"
        case 53: service = "DNS"
        case 22: service = "SSH"
        case 5223: service = "Apple 推送"
        case 445: service = "SMB 文件共享"
        case 7890, 7891, 6152, 1080: service = "本地代理"
        default: service = proto.uppercased()
        }
        return (prefix + service, isExternal, false)
    }

    public static func isPrivateOrLoopbackHost(_ host: String) -> Bool {
        if host.isEmpty || host == "*" || host == "::1" || host == "localhost" { return true }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("169.254.") || host.lowercased().hasPrefix("fe80:") {
            return true
        }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) { return true }
        }
        if host.hasPrefix("198.18.") || host.hasPrefix("198.19.") { return true }
        return false
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 { return String(format: "%.2f GB", Double(bytes) / 1_073_741_824.0) }
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576.0) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024.0) }
        return "\(bytes) B"
    }

    public static func formatRate(_ bps: Double) -> String {
        if bps >= 1_048_576 { return String(format: "%.2f MB/s", bps / 1_048_576.0) }
        if bps >= 1024 { return String(format: "%.1f KB/s", bps / 1024.0) }
        if bps >= 1 { return String(format: "%.0f B/s", bps) }
        return "0 B/s"
    }
}
