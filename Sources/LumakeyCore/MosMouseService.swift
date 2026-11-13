import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public struct MosConfig: Codable, Sendable, Hashable {
    public var enabled: Bool = false
    public var reverseWheelDirection: Bool = true
    public var smoothScroll: Bool = true
    public var stepPixels: Double = 36.0
    public var smoothness: Double = 0.24
    public var shiftHorizontal: Bool = true
    public var optionBoost: Bool = true
    public var excludedBundleIDs: [String] = []

    public init(
        enabled: Bool = false,
        reverseWheelDirection: Bool = true,
        smoothScroll: Bool = true,
        stepPixels: Double = 36.0,
        smoothness: Double = 0.24,
        shiftHorizontal: Bool = true,
        optionBoost: Bool = true,
        excludedBundleIDs: [String] = []
    ) {
        self.enabled = enabled
        self.reverseWheelDirection = reverseWheelDirection
        self.smoothScroll = smoothScroll
        self.stepPixels = stepPixels
        self.smoothness = smoothness
        self.shiftHorizontal = shiftHorizontal
        self.optionBoost = optionBoost
        self.excludedBundleIDs = excludedBundleIDs
    }

    public static func defaultConfigURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Lumakey", isDirectory: true).appendingPathComponent("mos-config.json")
    }

    public static func load(from url: URL = defaultConfigURL()) -> MosConfig {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(MosConfig.self, from: data)
        else { return MosConfig() }
        return decoded
    }

    public func save(to url: URL = defaultConfigURL()) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

public final class MosEngine: @unchecked Sendable {
    public static let shared = MosEngine()
    public static let syntheticEventTag: Int64 = 0x4C4D_4D4F

    private let lock = NSLock()
    private var _config = MosConfig()
    private var _isTapActive = false
    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var interpTimer: DispatchSourceTimer?
    private var appObserver: NSObjectProtocol?
    private var frontmostBundleID: String = ""
    private var pendingY: Double = 0
    private var pendingX: Double = 0

    private init() {}

    public var config: MosConfig { lock.withLock { _config } }
    public var isTapActive: Bool { lock.withLock { _isTapActive } }
    public var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    public func requestAccessibilityPermission() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [key: kCFBooleanTrue as Any] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    public func apply(config newConfig: MosConfig, persist: Bool = true) {
        if persist { newConfig.save() }
        lock.withLock { _config = newConfig }
        let needsTap = newConfig.enabled && (newConfig.reverseWheelDirection || newConfig.smoothScroll)
        if needsTap {
            DispatchQueue.main.async { self.startTapIfNeeded() }
        } else {
            DispatchQueue.main.async { self.stopTapAndReleaseAll() }
        }
    }

    public func stopTapAndReleaseAll() {
        stopInterpolator()
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        if let port = tapPort {
            CFMachPortInvalidate(port)
            tapPort = nil
        }
        if let obs = appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appObserver = nil
        }
        lock.withLock { _isTapActive = false }
    }

    private func startTapIfNeeded() {
        guard tapPort == nil else { return }
        guard AXIsProcessTrusted() else {
            lock.withLock { _isTapActive = false }
            return
        }
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontmostBundleID = app?.bundleIdentifier ?? ""
        }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let engine = Unmanaged<MosEngine>.fromOpaque(userInfo).takeUnretainedValue()
                return engine.handleScrollEvent(type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            lock.withLock { _isTapActive = false }
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tapPort = port
        runLoopSource = src
        lock.withLock { _isTapActive = true }
    }

    private func handleScrollEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let cfg = config
        guard type == .scrollWheel, cfg.enabled else { return Unmanaged.passUnretained(event) }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventTag {
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
            return Unmanaged.passUnretained(event)
        }
        if !frontmostBundleID.isEmpty && cfg.excludedBundleIDs.contains(frontmostBundleID) {
            return Unmanaged.passUnretained(event)
        }

        let sign: Double = cfg.reverseWheelDirection ? -1.0 : 1.0
        let flags = event.flags
        let shiftHorizontal = cfg.shiftHorizontal && flags.contains(.maskShift)
        let boost: Double = (cfg.optionBoost && flags.contains(.maskAlternate)) ? 3.0 : 1.0

        if !cfg.smoothScroll {
            applyDirectStepTransform(event: event, sign: sign, reverse: cfg.reverseWheelDirection, shiftHorizontal: shiftHorizontal)
            return Unmanaged.passUnretained(event)
        }

        let line1 = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let pt1 = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        let unit = line1 != 0 ? line1 : (pt1 / 10.0)
        let deltaPx = unit * sign * cfg.stepPixels * boost
        if shiftHorizontal {
            pendingX += deltaPx
        } else {
            pendingY += deltaPx
            pendingX += Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)) * sign * cfg.stepPixels
        }
        startInterpolatorIfNeeded()
        return nil
    }

    private func applyDirectStepTransform(event: CGEvent, sign: Double, reverse: Bool, shiftHorizontal: Bool) {
        let d1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let p1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let f1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        if shiftHorizontal {
            let mult = Int64(sign)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: d1 * mult)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: p1 * mult)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: f1 * sign)
        } else if reverse {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -d1)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -p1)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -f1)
        }
    }

    private func startInterpolatorIfNeeded() {
        guard interpTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tickInterpolator() }
        timer.resume()
        interpTimer = timer
    }

    private func tickInterpolator() {
        let factor = min(max(config.smoothness, 0.08), 0.55)
        let stepY = pendingY * factor
        let stepX = pendingX * factor
        pendingY -= stepY
        pendingX -= stepX

        let dy = Int32(stepY.rounded())
        let dx = Int32(stepX.rounded())
        if dy != 0 || dx != 0,
           let ev = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) {
            ev.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
            ev.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            ev.post(tap: .cgSessionEventTap)
        }
        if abs(pendingY) < 0.4 && abs(pendingX) < 0.4 {
            stopInterpolator()
        }
    }

    private func stopInterpolator() {
        interpTimer?.cancel()
        interpTimer = nil
        pendingY = 0
        pendingX = 0
    }
}
