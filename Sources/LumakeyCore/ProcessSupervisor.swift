import Darwin
import Dispatch
import Foundation

public struct ProcessRunResult: Sendable, Hashable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let durationMs: Int
    public let timedOut: Bool
}

public final class ProcessSupervisor: @unchecked Sendable {
    public static let shared = ProcessSupervisor()

    private let lock = NSLock()
    private var activePIDs = Set<Int32>()

    private init() {}

    public var activeCount: Int {
        lock.withLock { activePIDs.count }
    }

    public func run(
        executableURL: URL,
        arguments: [String] = [],
        currentDirectoryURL: URL? = nil,
        stdinData: Data? = nil,
        timeoutSeconds: Double = 8.0,
        maxOutputBytes: Int = 65_536
    ) throws -> ProcessRunResult {
        let started = ContinuousClock.now
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let pid = process.processIdentifier
        lock.withLock { _ = activePIDs.insert(pid) }

        let timeoutFlag = LockedBox(false)
        let timerItem = DispatchWorkItem { [weak self] in
            timeoutFlag.withValue { $0 = true }
            Self.terminateProcess(pid: pid)
            self?.removePID(pid)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timerItem)

        defer {
            timerItem.cancel()
            removePID(pid)
        }

        if let stdinData, !stdinData.isEmpty {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: stdinData)
        }
        try? stdinPipe.fileHandleForWriting.close()

        let outBox = LockedBox(Data())
        let errBox = LockedBox(Data())
        let readGroup = DispatchGroup()

        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let chunk = Self.readBounded(handle: stdoutPipe.fileHandleForReading, maxBytes: maxOutputBytes)
            outBox.withValue { $0 = chunk }
            readGroup.leave()
        }

        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let chunk = Self.readBounded(handle: stderrPipe.fileHandleForReading, maxBytes: maxOutputBytes)
            errBox.withValue { $0 = chunk }
            readGroup.leave()
        }

        process.waitUntilExit()
        readGroup.wait()

        let elapsed = started.duration(to: .now)
        let ms = Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        return ProcessRunResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outBox.snapshot(), encoding: .utf8) ?? "",
            stderr: String(data: errBox.snapshot(), encoding: .utf8) ?? "",
            durationMs: ms,
            timedOut: timeoutFlag.snapshot()
        )
    }

    public func terminateAll() {
        let snapshot = lock.withLock {
            let copy = activePIDs
            activePIDs.removeAll()
            return copy
        }
        for pid in snapshot where pid > 0 {
            kill(pid, SIGTERM)
        }
        if !snapshot.isEmpty {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.15) {
                for pid in snapshot where pid > 0 {
                    kill(pid, SIGKILL)
                }
            }
        }
    }

    private func removePID(_ pid: Int32) {
        lock.withLock { _ = activePIDs.remove(pid) }
    }

    private static func terminateProcess(pid: Int32) {
        guard pid > 0 else { return }
        kill(pid, SIGTERM)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
            kill(pid, SIGKILL)
        }
    }

    private static func readBounded(handle: FileHandle, maxBytes: Int) -> Data {
        defer { try? handle.close() }
        var collected = Data()
        while collected.count < maxBytes {
            let remaining = maxBytes - collected.count
            guard let chunk = try? handle.read(upToCount: min(8_192, remaining)), !chunk.isEmpty else {
                break
            }
            collected.append(chunk)
        }
        return collected
    }
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func withValue(_ mutate: (inout T) -> Void) {
        lock.withLock { mutate(&value) }
    }

    func snapshot() -> T {
        lock.withLock { value }
    }
}

public enum MemoryStats {
    public static func currentPhysicalFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576.0
    }

    public static func reclaimFreeHeapPages() {
        malloc_zone_pressure_relief(nil, 0)
    }
}
