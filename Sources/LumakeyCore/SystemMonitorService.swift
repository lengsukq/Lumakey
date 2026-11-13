import Darwin
import Foundation
import IOKit

public final class SystemMonitorSampler: @unchecked Sendable {
    private let chipBrand: String
    private let memoryTotalBytes: UInt64
    private let vmPageSize: UInt64
    private let batteryService: io_service_t
    private let gpuService: io_service_t
    private let perfCount: Int
    private let effCount: Int
    private let topologyText: String
    private let minEffGHz: Double
    private let maxEffGHz: Double
    private let maxPerfGHz: Double

    private var prevCPUTicks: [UInt32] = []
    private var prevNetIn: UInt64 = 0
    private var prevNetOut: UInt64 = 0
    private var prevNetTimestamp: CFAbsoluteTime = 0
    private var sampleTickCount: UInt64 = 0
    private var cachedDisk: (freeGB: Double, totalGB: Double) = (0, 0)
    private var cpuHist: [Double] = []
    private var memHist: [Double] = []
    private var powerHist: [Double] = []
    private var netHist: [Double] = []

    public init() {
        self.chipBrand = Self.sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        let mem = Self.sysctlUInt64("hw.memsize")
        self.memoryTotalBytes = mem > 0 ? mem : ProcessInfo.processInfo.physicalMemory
        var pageSize: vm_size_t = 16_384
        host_page_size(mach_host_self(), &pageSize)
        self.vmPageSize = UInt64(pageSize)
        self.batteryService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        self.gpuService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
        let p0 = Int(Self.sysctlUInt64("hw.perflevel0.logicalcpu"))
        let p1 = Int(Self.sysctlUInt64("hw.perflevel1.logicalcpu"))
        let p2 = Int(Self.sysctlUInt64("hw.perflevel2.logicalcpu"))
        let totalLogical = max(1, Int(Self.sysctlUInt64("hw.ncpu")))
        let highCores = p2 > 0 ? (p0 + p1) : (p0 > 0 ? p0 : max(1, totalLogical / 2))
        let lowCores = p2 > 0 ? p2 : (p1 > 0 ? p1 : max(0, totalLogical - highCores))
        self.perfCount = min(highCores, totalLogical)
        self.effCount = max(0, totalLogical - self.perfCount)
        self.topologyText = lowCores > 0 ? "\(totalLogical)核 (\(self.perfCount)P+\(self.effCount)E)" : "\(totalLogical)核"
        let freqBounds = Self.readDVFSBounds()
        self.minEffGHz = freqBounds.minEffGHz
        self.maxEffGHz = freqBounds.maxEffGHz
        self.maxPerfGHz = freqBounds.maxPerfGHz
        cpuHist.reserveCapacity(25); memHist.reserveCapacity(25)
        powerHist.reserveCapacity(25); netHist.reserveCapacity(25)
    }

    deinit {
        if batteryService != 0 { IOObjectRelease(batteryService) }
        if gpuService != 0 { IOObjectRelease(gpuService) }
    }

    public func sample() -> SystemTelemetrySnapshot {
        let cpu = sampleCPU(), mem = sampleMemory(), power = samplePowerAndBattery()
        let gpu = sampleGPUUtilization(), net = sampleNetworkRate()
        if sampleTickCount % 10 == 0 {
            cachedDisk = sampleDiskSpace()
        }
        sampleTickCount &+= 1
        let disk = cachedDisk
        let effEst = minEffGHz + max(0.2, maxEffGHz - minEffGHz) * (cpu.eff / 100.0)
        let perfEst = maxEffGHz + max(0.2, maxPerfGHz - maxEffGHz) * pow(cpu.perf / 100.0, 0.72)
        let weight = min(1.0, max(cpu.perf / 100.0, cpu.total / 100.0))
        let estGHz = min(maxPerfGHz, max(minEffGHz, effEst * (1.0 - weight) + perfEst * weight))

        appendHistory(&cpuHist, value: cpu.total / 100.0)
        appendHistory(&memHist, value: mem.percent / 100.0)
        appendHistory(&powerHist, value: min(1.0, power.watts / 45.0))
        appendHistory(&netHist, value: min(1.0, log10(max(1.0, (net.down + net.up) / 1024.0)) / 5.0))

        var snap = SystemTelemetrySnapshot()
        snap.cpuTotalPercent = cpu.total; snap.perfCorePercent = cpu.perf; snap.effCorePercent = cpu.eff
        snap.estimatedFrequencyGHz = estGHz; snap.maxFrequencyGHz = maxPerfGHz
        snap.chipBrand = chipBrand; snap.coreTopologyText = topologyText; snap.thermalStateLabel = Self.thermalLabel()
        snap.gpuPercent = gpu
        snap.memoryUsedBytes = mem.used; snap.memoryTotalBytes = memoryTotalBytes
        snap.memoryPercent = mem.percent; snap.memoryCompressedBytes = mem.compressed; snap.swapUsedMB = mem.swapMB
        snap.systemWatts = power.watts; snap.batteryPercent = power.batteryPct; snap.isCharging = power.isCharging
        snap.netDownBytesPerSec = net.down; snap.netUpBytesPerSec = net.up
        snap.diskFreeGB = disk.freeGB; snap.diskTotalGB = disk.totalGB
        snap.cpuHistory = cpuHist; snap.memHistory = memHist; snap.powerHistory = powerHist; snap.netHistory = netHist
        return snap
    }

    private func appendHistory(_ array: inout [Double], value: Double) {
        array.append(min(1.0, max(0.0, value)))
        if array.count > 24 { array.removeFirst(array.count - 24) }
    }

    private func sampleCPU() -> (total: Double, perf: Double, eff: Double) {
        var numCPUs: natural_t = 0, cpuInfo: processor_info_array_t?, numCPUInfo: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCPUInfo) == KERN_SUCCESS,
              let cpuInfo else { return (0, 0, 0) }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(Int(numCPUInfo) * MemoryLayout<integer_t>.stride)) }
        let coreCount = Int(numCPUs)
        let current = (0..<Int(numCPUInfo)).map { UInt32(bitPattern: cpuInfo[$0]) }
        defer { prevCPUTicks = current }
        guard prevCPUTicks.count == current.count, coreCount > 0 else { return (0, 0, 0) }

        let stride = Int(CPU_STATE_MAX)
        var allActive = 0.0, allTotal = 0.0, pActive = 0.0, pTotal = 0.0, eActive = 0.0, eTotal = 0.0
        for core in 0..<coreCount {
            let b = core * stride
            let u = current[b + Int(CPU_STATE_USER)] &- prevCPUTicks[b + Int(CPU_STATE_USER)]
            let s = current[b + Int(CPU_STATE_SYSTEM)] &- prevCPUTicks[b + Int(CPU_STATE_SYSTEM)]
            let i = current[b + Int(CPU_STATE_IDLE)] &- prevCPUTicks[b + Int(CPU_STATE_IDLE)]
            let n = current[b + Int(CPU_STATE_NICE)] &- prevCPUTicks[b + Int(CPU_STATE_NICE)]
            let active = Double(u &+ s &+ n), total = active + Double(i)
            allActive += active; allTotal += total
            if core < perfCount { pActive += active; pTotal += total } else { eActive += active; eTotal += total }
        }
        let totalPct = allTotal > 0 ? (allActive / allTotal) * 100.0 : 0
        return (totalPct, pTotal > 0 ? (pActive / pTotal) * 100.0 : totalPct, eTotal > 0 ? (eActive / eTotal) * 100.0 : totalPct)
    }

    private func sampleMemory() -> (used: UInt64, percent: Double, compressed: UInt64, swapMB: Double) {
        var vm = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &vm) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        var used: UInt64 = 0, compressed: UInt64 = 0
        if kr == KERN_SUCCESS {
            let comp = UInt64(vm.compressor_page_count)
            used = min(memoryTotalBytes, (UInt64(vm.active_count) + UInt64(vm.wire_count) + comp) * vmPageSize)
            compressed = comp * vmPageSize
        }
        var swap = xsw_usage(), swapSize = MemoryLayout<xsw_usage>.size
        let swapMB = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 ? Double(swap.xsu_used) / 1_048_576.0 : 0
        return (used, memoryTotalBytes > 0 ? (Double(used) / Double(memoryTotalBytes)) * 100.0 : 0, compressed, swapMB)
    }

    private func samplePowerAndBattery() -> (watts: Double, batteryPct: Int?, isCharging: Bool) {
        guard batteryService != 0 else { return (0, nil, false) }
        return autoreleasepool {
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(batteryService, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any] else { return (0, nil, false) }
            var watts = 0.0
            if let telemetry = props["PowerTelemetryData"] as? [String: Any] {
                if let loadMW = telemetry["SystemLoad"] as? NSNumber, loadMW.doubleValue > 0 { watts = loadMW.doubleValue / 1000.0 }
                else if let pinMW = telemetry["SystemPowerIn"] as? NSNumber, pinMW.doubleValue > 0 { watts = pinMW.doubleValue / 1000.0 }
            }
            if watts <= 0, let v = (props["Voltage"] as? NSNumber)?.doubleValue, let a = (props["InstantAmperage"] as? NSNumber ?? props["Amperage"] as? NSNumber)?.doubleValue {
                watts = abs(v * a) / 1_000_000.0
            }
            let installed = (props["BatteryInstalled"] as? Bool) ?? ((props["MaxCapacity"] as? Int ?? 0) > 0)
            var pct: Int? = nil
            if installed, let cur = (props["CurrentCapacity"] as? NSNumber)?.doubleValue, let maxCap = (props["MaxCapacity"] as? NSNumber)?.doubleValue, maxCap > 0 {
                pct = max(0, min(100, Int((cur / maxCap * 100.0).rounded())))
            }
            return (watts, pct, (props["IsCharging"] as? Bool) ?? false)
        }
    }

    private func sampleGPUUtilization() -> Double {
        guard gpuService != 0 else { return 0 }
        return autoreleasepool {
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(gpuService, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any],
                  let perf = props["PerformanceStatistics"] as? [String: Any] else { return 0 }
            return (perf["Device Utilization %"] as? NSNumber ?? perf["Renderer Utilization %"] as? NSNumber)?.doubleValue ?? 0
        }
    }

    private func sampleNetworkRate() -> (down: Double, up: Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(first) }
        var totalIn: UInt64 = 0, totalOut: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = cursor {
            if let addr = cur.pointee.ifa_addr, Int32(addr.pointee.sa_family) == AF_LINK, let dataPtr = cur.pointee.ifa_data {
                let name = String(cString: cur.pointee.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("pdp_ip") {
                    let netData = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                    totalIn &+= UInt64(netData.ifi_ibytes); totalOut &+= UInt64(netData.ifi_obytes)
                }
            }
            cursor = cur.pointee.ifa_next
        }
        let now = CFAbsoluteTimeGetCurrent()
        defer { prevNetIn = totalIn; prevNetOut = totalOut; prevNetTimestamp = now }
        let dt = now - prevNetTimestamp
        guard prevNetTimestamp > 0, dt > 0.05 else { return (0, 0) }
        return (totalIn >= prevNetIn ? Double(totalIn - prevNetIn) / dt : 0, totalOut >= prevNetOut ? Double(totalOut - prevNetOut) / dt : 0)
    }

    private func sampleDiskSpace() -> (freeGB: Double, totalGB: Double) {
        var stats = statfs()
        guard statfs("/", &stats) == 0 else { return (0, 0) }
        let gb = 1_000_000_000.0
        return (Double(stats.f_bavail) * Double(stats.f_bsize) / gb, Double(stats.f_blocks) * Double(stats.f_bsize) / gb)
    }

    private static func readDVFSBounds() -> (minEffGHz: Double, maxEffGHz: Double, maxPerfGHz: Double) {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/arm-io/pmgr")
        guard entry != 0 else { return (1.0, 2.6, 4.2) }
        defer { IOObjectRelease(entry) }
        let pFreqs = parseFreqTable(entry: entry, key: "voltage-states5-sram")
        let eFreqs = parseFreqTable(entry: entry, key: "voltage-states1-sram")
        let maxEff = eFreqs.max() ?? 2.6
        return (eFreqs.min() ?? 1.0, maxEff, max(pFreqs.max() ?? 4.2, maxEff + 0.5))
    }

    private static func parseFreqTable(entry: io_registry_entry_t, key: String) -> [Double] {
        guard let cfData = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data else { return [] }
        var result: [Double] = []
        cfData.withUnsafeBytes { raw in
            for i in 0..<(cfData.count / 8) {
                let rawVal = raw.loadUnaligned(fromByteOffset: i * 8, as: UInt32.self)
                guard rawVal > 0 else { continue }
                let ghz = rawVal > 10_000_000 ? Double(rawVal) / 1_000_000_000.0 : Double(rawVal) / 1_000_000.0
                if ghz >= 0.3 && ghz <= 8.0 { result.append(ghz) }
            }
        }
        return result
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0; guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func sysctlUInt64(_ name: String) -> UInt64 {
        var val: UInt64 = 0, size = MemoryLayout<UInt64>.size
        if sysctlbyname(name, &val, &size, nil, 0) == 0 { return val }
        var val32: UInt32 = 0, size32 = MemoryLayout<UInt32>.size
        return sysctlbyname(name, &val32, &size32, nil, 0) == 0 ? UInt64(val32) : 0
    }

    private static func thermalLabel() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "正常"; case .fair: "温热"; case .serious: "较高"; case .critical: "过热降频"; @unknown default: "正常"
        }
    }
}