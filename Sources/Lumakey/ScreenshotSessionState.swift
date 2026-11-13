import AppKit
import CoreGraphics
import LumakeyCore
import SwiftUI

enum ScreenshotMode: Sendable {
    case interactiveAnnotate
    case quickOCR
}

enum ScreenshotResult: Sendable {
    case copied(URL)
    case saved(URL)
    case pinned(URL, NSRect)
    case ocrRequested(URL)
    case cutoutRequested(URL)
    case cancelled
}

struct DetectedScreenWindow: Identifiable, Sendable {
    let id: CGWindowID
    let ownerName: String
    let title: String
    let frame: CGRect
}

enum SelectionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}

enum ScreenshotDragMode {
    case creating(CGPoint)
    case resizing(SelectionHandle, CGRect)
    case movingSelection(CGRect, CGPoint, [ScreenshotAnnotation])
    case annotating(AnnotationToolKind)
    case noop
}

@MainActor
final class ScreenshotSessionState: ObservableObject {
    let baseImage: CGImage
    let pixelatedImage: CGImage?
    let screenBounds: CGRect
    let appKitScreenFrame: NSRect
    let windows: [DetectedScreenWindow]
    let mode: ScreenshotMode

    @Published var selectionRect: CGRect?
    @Published var hoveredWindowRect: CGRect?
    @Published var cursorPoint: CGPoint
    @Published var cursorHex: String = "#000000"
    @Published var isDraggingSelection: Bool = false
    @Published var activeTool: AnnotationToolKind = .move
    @Published var selectedColor: AnnotationRGBColor = AnnotationRGBColor.presets[0]
    @Published var strokeSize: AnnotationStrokeSize = .medium
    @Published var annotations: [ScreenshotAnnotation] = []
    @Published var draftAnnotation: ScreenshotAnnotation?
    @Published var nextCounterIndex: Int = 1
    @Published var pendingTextPoint: CGPoint?
    @Published var pendingTextValue: String = ""
    @Published var bannerMessage: String?
    @Published var hasAutoCopied: Bool = false

    var backingScale: CGFloat {
        guard screenBounds.width > 0 else { return 2.0 }
        return max(1.0, CGFloat(baseImage.width) / screenBounds.width)
    }

    var activeDragMode: ScreenshotDragMode?
    var lastTapTimestamp: TimeInterval = 0
    var lastTapPoint: CGPoint = .zero

    init(baseImage: CGImage, screenBounds: CGRect, appKitScreenFrame: NSRect, windows: [DetectedScreenWindow], mode: ScreenshotMode) {
        self.baseImage = baseImage
        self.pixelatedImage = ScreenshotCompositor.makePixelatedPreview(from: baseImage, cellPixelSize: 16)
        self.screenBounds = screenBounds
        self.appKitScreenFrame = appKitScreenFrame
        self.windows = windows
        self.mode = mode
        let center = CGPoint(x: screenBounds.midX, y: screenBounds.midY)
        self.cursorPoint = center
        self.cursorHex = ScreenshotCompositor.samplePixelColor(in: baseImage, point: center, screenBounds: screenBounds)
    }

    func updateHover(at point: CGPoint) {
        cursorPoint = point
        cursorHex = ScreenshotCompositor.samplePixelColor(in: baseImage, point: point, screenBounds: screenBounds)
        guard selectionRect == nil else {
            hoveredWindowRect = nil
            return
        }
        hoveredWindowRect = windows.first(where: { $0.frame.contains(point) })?.frame
    }

    func commitTextAnnotation() {
        guard let pt = pendingTextPoint else { return }
        let trimmed = pendingTextValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            annotations.append(ScreenshotAnnotation(
                tool: .text, color: selectedColor, strokeSize: strokeSize, points: [pt], text: trimmed
            ))
        }
        pendingTextPoint = nil
        pendingTextValue = ""
    }

    func undoAnnotation() {
        guard !annotations.isEmpty else { return }
        let removed = annotations.removeLast()
        if removed.tool == .counter {
            nextCounterIndex = max(1, removed.counterIndex)
        }
    }

    func moveSelection(from initial: CGRect, initialAnnotations: [ScreenshotAnnotation], dx: CGFloat, dy: CGFloat) {
        let clampedX = min(max(0, initial.minX + dx), screenBounds.width - initial.width)
        let clampedY = min(max(0, initial.minY + dy), screenBounds.height - initial.height)
        let appliedDX = clampedX - initial.minX
        let appliedDY = clampedY - initial.minY
        selectionRect = CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: initial.size)
        if !initialAnnotations.isEmpty {
            annotations = initialAnnotations.map { item in
                var moved = item
                moved.points = item.points.map { CGPoint(x: $0.x + appliedDX, y: $0.y + appliedDY) }
                return moved
            }
        }
    }

    func clearAnnotations() {
        annotations.removeAll()
        draftAnnotation = nil
        pendingTextPoint = nil
        pendingTextValue = ""
        nextCounterIndex = 1
    }

    func screenRectForSelection() -> NSRect? {
        guard let rect = selectionRect?.standardized, rect.width >= 4, rect.height >= 4 else { return nil }
        return NSRect(
            x: appKitScreenFrame.minX + rect.minX,
            y: appKitScreenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
