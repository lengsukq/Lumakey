import Darwin
import Foundation

public final class NetworkTrafficSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previousCounters: [Int32: (bytesIn: Int64, bytesOut: Int64)] = [:]
    private var lastSampleTime: Date?
    private var pidMetaCache: [Int32: (displayName: String, executablePath: String?, bundleAppPath: String?)] = [:]

    public init() {}

    public func sample() -> NetworkTrafficSnapshot {
        let now = Date()
        guard let res = try? ProcessSupervisor.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/nettop"),
            arguments: ["-L", "1", "-J", "bytes_in,bytes_out,interface,state", "-x", "-n"],
            timeoutSeconds: 4.5,
            maxOutputBytes: 524_288
        ), !res.stdout.isEmpty else {
            return .empty
        }

        lock.lock()
        let prev = previousCounters
        let elapsed = lastSampleTime.map { now.timeIntervalSince($0) } ?? 0
        lock.unlock()

        let parsed = NetworkTrafficParser.parseNettopCSV(res.stdout, previous: prev, elapsed: elapsed, sampledAt: now) { pid, procName in
            self.resolveProcessMetadata(pid: pid, fallbackName: procName)
        }

        lock.lock()
        previousCounters = parsed.counters
        lastSampleTime = now
        if pidMetaCache.count > 400 { pidMetaCache.removeAll(keepingCapacity: true) }
        lock.unlock()
        return parsed.snapshot
    }

    private func resolveProcessMetadata(pid: Int32, fallbackName: String) -> (displayName: String, executablePath: String?, bundleAppPath: String?) {
        lock.lock()
        if let cached = pidMetaCache[pid] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let meta = Self.lookupProcessMetadata(pid: pid, fallbackName: fallbackName)
        lock.lock()
        pidMetaCache[pid] = meta
        lock.unlock()
        return meta
    }

    private static func lookupProcessMetadata(pid: Int32, fallbackName: String) -> (displayName: String, executablePath: String?, bundleAppPath: String?) {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let len = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard len > 0 else { return (fallbackName, nil, nil) }
        let bytes = buffer.prefix(Int(len)).map { UInt8(bitPattern: $0) }
        let execPath = String(decoding: bytes, as: UTF8.self)
        var bundleAppPath: String?
        var displayName = fallbackName

        var cursor = URL(fileURLWithPath: execPath)
        for _ in 0..<8 {
            let parent = cursor.deletingLastPathComponent()
            if cursor.pathExtension == "app" {
                bundleAppPath = cursor.path
                displayName = cursor.deletingPathExtension().lastPathComponent
                break
            }
            if parent.path == cursor.path { break }
            cursor = parent
        }
        if bundleAppPath == nil {
            let base = URL(fileURLWithPath: execPath).lastPathComponent
            if !base.isEmpty && base.count >= fallbackName.count { displayName = base }
        }
        return (displayName, execPath, bundleAppPath)
    }

    public static func reverseDNS(ip: String) -> String? {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "*", !NetworkTrafficParser.isPrivateOrLoopbackHost(trimmed) else { return nil }

        var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        var addr4 = in_addr()
        if trimmed.withCString({ inet_pton(AF_INET, $0, &addr4) }) == 1 {
            var sin = sockaddr_in()
            sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            sin.sin_family = sa_family_t(AF_INET)
            sin.sin_addr = addr4
            let rc = withUnsafePointer(to: &sin) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &hostBuf, socklen_t(hostBuf.count), nil, 0, NI_NAMEREQD)
                }
            }
            if rc == 0 {
                return String(decoding: hostBuf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }

        var addr6 = in6_addr()
        if trimmed.withCString({ inet_pton(AF_INET6, $0, &addr6) }) == 1 {
            var sin6 = sockaddr_in6()
            sin6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            sin6.sin6_family = sa_family_t(AF_INET6)
            sin6.sin6_addr = addr6
            let rc = withUnsafePointer(to: &sin6) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in6>.size), &hostBuf, socklen_t(hostBuf.count), nil, 0, NI_NAMEREQD)
                }
            }
            if rc == 0 {
                return String(decoding: hostBuf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        return nil
    }
}
