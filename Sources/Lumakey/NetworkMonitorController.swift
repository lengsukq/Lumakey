import AppKit
import Foundation
import LumakeyCore
import SwiftUI

@MainActor
final class NetworkMonitorController: ObservableObject {
    @Published var snapshot: NetworkTrafficSnapshot = .empty
    @Published var filterMode: NetworkFilterMode = .all
    @Published var sortField: NetworkSortField = .liveRate
    @Published var searchText: String = ""
    @Published var isPaused: Bool = false
    @Published var isSampling: Bool = false
    @Published var selectedPID: Int32?
    @Published var resolvedHosts: [String: String] = [:]

    private let sampler = NetworkTrafficSampler()
    private var sampleTask: Task<Void, Never>?
    private var dnsTask: Task<Void, Never>?
    private var inFlightDNS: Set<String> = []

    func start() {
        guard sampleTask == nil else { return }
        sampleTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                if !self.isPaused {
                    self.isSampling = true
                    let sampler = self.sampler
                    let snap = await Task.detached(priority: .utility) { sampler.sample() }.value
                    guard !Task.isCancelled else { break }
                    self.snapshot = snap
                    self.isSampling = false
                    self.ensureValidSelection()
                    self.resolveDNSForSelection()
                }
                try? await Task.sleep(for: .milliseconds(2000))
            }
        }
    }

    func stop() {
        sampleTask?.cancel()
        sampleTask = nil
        dnsTask?.cancel()
        dnsTask = nil
        isSampling = false
    }

    func togglePaused() {
        isPaused.toggle()
        if !isPaused { refreshNow() }
    }

    func refreshNow() {
        let sampler = self.sampler
        isSampling = true
        Task { [weak self] in
            let snap = await Task.detached(priority: .userInitiated) { sampler.sample() }.value
            guard let self else { return }
            self.snapshot = snap
            self.isSampling = false
            self.ensureValidSelection()
            self.resolveDNSForSelection()
        }
    }

    func selectProcess(_ pid: Int32) {
        selectedPID = pid
        resolveDNSForSelection()
    }

    var filteredProcesses: [ProcessTrafficSummary] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = snapshot.processes.filter { proc in
            switch filterMode {
            case .all: break
            case .activeRate: guard proc.totalRate > 1 else { return false }
            case .externalOnly: guard proc.hasExternalConnection else { return false }
            case .listening: guard proc.hasListeningSocket else { return false }
            }
            guard !needle.isEmpty else { return true }
            if proc.displayName.localizedCaseInsensitiveContains(needle)
                || proc.processName.localizedCaseInsensitiveContains(needle)
                || "\(proc.pid)".contains(needle) {
                return true
            }
            return proc.connections.contains { conn in
                conn.remoteHost.localizedCaseInsensitiveContains(needle)
                    || conn.serviceTag.localizedCaseInsensitiveContains(needle)
                    || (resolvedHosts[conn.remoteHost]?.localizedCaseInsensitiveContains(needle) ?? false)
            }
        }

        return list.sorted { lhs, rhs in
            switch sortField {
            case .liveRate:
                if lhs.totalRate != rhs.totalRate { return lhs.totalRate > rhs.totalRate }
                return lhs.totalBytes > rhs.totalBytes
            case .totalBytes:
                if lhs.totalBytes != rhs.totalBytes { return lhs.totalBytes > rhs.totalBytes }
                return lhs.totalRate > rhs.totalRate
            case .connections:
                if lhs.connections.count != rhs.connections.count { return lhs.connections.count > rhs.connections.count }
                return lhs.totalBytes > rhs.totalBytes
            case .name:
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    var selectedProcess: ProcessTrafficSummary? {
        let filtered = filteredProcesses
        if let selectedPID, let hit = filtered.first(where: { $0.pid == selectedPID }) {
            return hit
        }
        return filtered.first
    }

    private func ensureValidSelection() {
        let filtered = filteredProcesses
        if let selectedPID, filtered.contains(where: { $0.pid == selectedPID }) { return }
        selectedPID = filtered.first?.pid
    }

    private func resolveDNSForSelection() {
        guard let proc = selectedProcess else { return }
        var candidates: [String] = []
        for conn in proc.connections where conn.isExternal && !conn.remoteHost.isEmpty {
            let ip = conn.remoteHost
            if resolvedHosts[ip] == nil && !inFlightDNS.contains(ip) && !candidates.contains(ip) {
                candidates.append(ip)
            }
            if candidates.count >= 10 { break }
        }
        guard !candidates.isEmpty else { return }
        for ip in candidates { inFlightDNS.insert(ip) }
        dnsTask = Task.detached(priority: .utility) { [weak self] in
            var found: [String: String] = [:]
            for ip in candidates {
                if Task.isCancelled { break }
                if let name = NetworkTrafficSampler.reverseDNS(ip: ip) { found[ip] = name }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                for ip in candidates {
                    self.inFlightDNS.remove(ip)
                    if let name = found[ip] {
                        if self.resolvedHosts.count > 256 { self.resolvedHosts.removeAll(keepingCapacity: true) }
                        self.resolvedHosts[ip] = name
                    }
                }
            }
        }
    }
}
