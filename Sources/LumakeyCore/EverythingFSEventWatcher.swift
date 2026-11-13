import CoreServices
import Foundation

public final class EverythingFSEventWatcher: @unchecked Sendable {
    private final class CallbackBox {
        let queue: DispatchQueue
        let debounceInterval: TimeInterval
        let onBatch: @Sendable (Set<String>) -> Void
        var pendingDirectories: Set<String> = []
        var flushWorkItem: DispatchWorkItem?

        init(
            queue: DispatchQueue,
            debounceInterval: TimeInterval,
            onBatch: @escaping @Sendable (Set<String>) -> Void
        ) {
            self.queue = queue
            self.debounceInterval = debounceInterval
            self.onBatch = onBatch
        }

        func enqueue(_ dirs: [String]) {
            guard !dirs.isEmpty else { return }
            pendingDirectories.formUnion(dirs)
            flushWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let batch = self.pendingDirectories
                self.pendingDirectories.removeAll()
                self.flushWorkItem = nil
                guard !batch.isEmpty else { return }
                self.onBatch(batch)
            }
            flushWorkItem = item
            queue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
        }
    }

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.queensu.lumakey.fsevents", qos: .utility)
    private let box: CallbackBox
    private var stopped = false

    public init?(
        roots: [URL],
        debounceInterval: TimeInterval = 0.8,
        onChangedDirectories: @escaping @Sendable (Set<String>) -> Void
    ) {
        var seen = Set<String>()
        var watchPaths: [String] = []
        for root in roots {
            let resolved = root.resolvingSymlinksInPath().standardizedFileURL.path
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir),
               isDir.boolValue,
               seen.insert(resolved).inserted {
                watchPaths.append(resolved)
            }
        }
        guard !watchPaths.isEmpty else { return nil }

        let box = CallbackBox(queue: queue, debounceInterval: debounceInterval, onBatch: onChangedDirectories)
        self.box = box

        let retained = Unmanaged.passRetained(box).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: retained,
            retain: nil,
            release: { ptr in
                guard let ptr else { return }
                Unmanaged<CallbackBox>.fromOpaque(ptr).release()
            },
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagFileEvents
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self)
            var dirs: [String] = []
            dirs.reserveCapacity(numEvents)
            for i in 0..<numEvents {
                guard let rawPath = paths[i] as? String else { continue }
                let clean = rawPath.hasSuffix("/") && rawPath.count > 1 ? String(rawPath.dropLast()) : rawPath
                let flag = eventFlags[i]
                if (flag & UInt32(kFSEventStreamEventFlagItemIsDir)) != 0 {
                    dirs.append((clean as NSString).deletingLastPathComponent)
                    dirs.append(clean)
                } else {
                    dirs.append((clean as NSString).deletingLastPathComponent)
                }
            }
            box.enqueue(dirs)
        }

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            watchPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) else {
            Unmanaged<CallbackBox>.fromOpaque(retained).release()
            return nil
        }

        self.stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    public func stop() {
        queue.sync {
            guard !stopped, let stream else { return }
            stopped = true
            box.flushWorkItem?.cancel()
            box.flushWorkItem = nil
            box.pendingDirectories.removeAll()
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit {
        if !stopped, let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
